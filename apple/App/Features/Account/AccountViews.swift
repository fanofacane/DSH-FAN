// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/account/account_page.dart.
import DSHClient
import SafariServices
import SwiftUI

/// The engine owns PKCE and the stored grant. Only display-safe state and the
/// short-lived browser destination enter the app; neither is logged or saved.
struct DeepSeekAccountPage: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    @Environment(HostStore.self) private var hosts
    @State private var view = AccountState()
    @State private var profile = AccountProfile()
    @State private var wallets: [AccountWallet] = []
    @State private var error: String?
    @State private var busy = false
    @State private var browser: AccountBrowserDestination?
    @State private var openedAttempt: String?
    @State private var confirmSignOut = false
    private var fixture: String? {
        #if DEBUG
        if DebugPageRegistry.usesFixture { return DebugPageRegistry.argument("-dsh-screen-fixture") }
        #endif
        return nil
    }
    private var signedIn: Bool { fixture == "signed-in" || view.status == "credential-stored" }
    private var remote: Bool { fixture == "remote" || hosts.isRemote }
    private var displayName: String? { fixture == "signed-in" ? "Example" : profile.name ?? profile.contact }
    private var attempt: AccountAttempt { view.attempt }
    private var phase: String { attempt.phase ?? "" }
    private var active: Bool { ["initializing", "waiting-browser", "exchanging", "committing"].contains(phase) }
    static var metadata: AccountClientInfo {
        AccountClientInfo(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0",
            locale: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"), timezoneOffsetSeconds: TimeZone.current.secondsFromGMT())
    }
    var body: some View {
        SettingsPage(title: "DeepSeek account") {
            if remote {
                SettingsGroup {
                    SettingsRow(glyph: AppIcon.remoteHost, title: "Remote host",
                                subtitle: String(localized: "Account sign-in is available only on this phone’s engine.")) { EmptyView() }
                }
            } else {
                OverviewCard(title: displayName.map { Text(verbatim: $0) } ?? Text("DeepSeek"),
                             subtitle: Text(signedIn ? "Signed in" : "Signed out")) {
                    SettingsIcon(glyph: AppIcon.profile, size: 52)
                } accessory: {
                    if active { ProgressView() }
                    else { StatusDot(tone: signedIn ? .ok : .idle) }
                } footer: {
                    if active { OverviewFooter(tone: .busy, text: Text(phaseTitle)) }
                }
                if fixture == "signed-in" {
                    SettingsGroup(header: "Account balance") {
                        InfoRow(label: "Paid credit", value: "¥28.50")
                        InfoRow(label: "Bonus credit", value: "¥10.00")
                    }
                } else if !wallets.isEmpty {
                    SettingsGroup(header: "Account balance") {
                        ForEach(Array(wallets.enumerated()), id: \.offset) { _, wallet in
                            SettingsRow(title: wallet.bonus ? "Bonus credit" : "Paid credit",
                                        subtitle: money(wallet)) { EmptyView() }
                        }
                    }
                }
                if let code = error ?? attempt.errorCode {
                    Text("Request failed: \(code)").type(.bodySmall).foregroundStyle(DS.danger).padding(.bottom, 12)
                }
                if active {
                    if phase == "waiting-browser" { MistButton(title: "Open authorization page") { openBrowser() }.padding(.bottom, 12) }
                    MistButton(title: "Cancel sign-in", kind: .secondary) { Task { await cancel() } }
                } else if signedIn {
                    MistButton(title: "Refresh balance", kind: .secondary, busy: busy) { Task { await refreshDetails() } }
                    Link(destination: URL(string: "https://platform.deepseek.com/top_up")!) { Text("Top up on DeepSeek") }
                        .type(.bodyMedium).foregroundStyle(theme.accent).padding(.vertical, 16)
                    MistButton(title: "Sign out", kind: .danger) { confirmSignOut = true }
                } else {
                    MistButton(title: "Sign in with DeepSeek", busy: busy) { Task { await signIn() } }.disabled(busy || chat.connection.state != .ready)
                    Text("Authorize in Safari. The engine receives the callback at 127.0.0.1 and stores the account grant.")
                        .type(.bodySmall).foregroundStyle(DS.inkFaint).padding(.top, 12)
                }
                SettingsGroup {
                    SettingsLink(glyph: AppIcon.configure, title: "Use an API key instead") { KeySettingsPage() }
                }.padding(.top, Space.lg)
            }
        }
        .task(id: "\(chat.connection.generation)-\(chat.connection.state == .ready)") {
            guard fixture == nil, chat.connection.state == .ready, !remote else { return }
            await watch()
        }
        .disabled(fixture != nil)
        .sheet(item: $browser) { destination in AccountSafari(url: destination.url).ignoresSafeArea() }
        .confirmationDialog("Sign out of the DeepSeek account?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await signOut() } }
        } message: { Text("Account tasks may stop. Your API keys are kept.") }
    }
    private var phaseTitle: LocalizedStringKey {
        switch phase {
        case "waiting-browser": "Waiting for browser authorization"
        case "exchanging", "committing": "Finishing sign-in"
        default: "Preparing sign-in"
        }
    }
    private func money(_ wallet: AccountWallet) -> String {
        let code = wallet.currency ?? ""
        let number = NSDecimalNumber(string: wallet.balance ?? "", locale: Locale(identifier: "en_US_POSIX"))
        guard number != .notANumber else { return code + " —" }
        let formatter = NumberFormatter(); formatter.numberStyle = .currency; formatter.currencyCode = code
        return formatter.string(from: number) ?? (code + " " + number.stringValue)
    }
    private func accept(_ next: AccountState) async {
        guard ["credential-stored", "signed-out"].contains(next.status ?? "") else {
            error = "E_ACCOUNT_STATE"; return
        }
        let previouslySignedIn = signedIn
        view = next
        if !signedIn { profile = AccountProfile(); wallets = [] }
        if phase == "waiting-browser", openedAttempt != attempt.id { openBrowser() }
        if signedIn && !previouslySignedIn {
            browser = nil
            do {
                try await chat.connection.commandsAPI.initializeDefaultModel()
                try await chat.connection.reloadModels()
                await refreshDetails()
            } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
        }
        if !active && !signedIn { browser = nil }
    }
    private func watch() async {
        let generation = chat.connection.generation
        while !Task.isCancelled && generation == chat.connection.generation {
            do {
                let frames = try await chat.connection.accountAPI.watch()
                for try await frame in frames {
                    guard !Task.isCancelled, generation == chat.connection.generation else { return }
                    error = nil; await accept(frame)
                }
            } catch { if !Task.isCancelled, generation == chat.connection.generation { self.error = appErrorCode(error) } }
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
        }
    }
    private func openBrowser() {
        guard let text = attempt.authorizeUrl, let url = URL(string: text),
              url.scheme == "https", url.host == "platform.deepseek.com" else { error = "E_ACCOUNT_AUTH_URL"; return }
        openedAttempt = attempt.id
        browser = AccountBrowserDestination(url: url)
    }
    private func signIn() async {
        busy = true; error = nil; defer { busy = false }
        do {
            let next = try await chat.connection.accountAPI.startSignIn(client: Self.metadata, callbackOrigin: "http://127.0.0.1:3080")
            await accept(next)
        } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
    }
    private func cancel() async {
        guard let id = attempt.id else { return }
        do { await accept(try await chat.connection.accountAPI.cancelSignIn(attemptId: id)) }
        catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
    }
    private func signOut() async {
        busy = true; defer { busy = false }
        do {
            await accept(try await chat.connection.accountAPI.signOut(client: Self.metadata))
            guard view.status == "signed-out" else { throw DSHError("E_ACCOUNT_SIGNOUT") }
            profile = AccountProfile(); wallets = []
            try await chat.connection.reloadModels()
        } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
    }
    private func refreshDetails() async {
        busy = true; defer { busy = false }
        do {
            profile = try await chat.connection.accountAPI.getProfile(client: Self.metadata)
            // Account grants stay inside the engine. Its account API reads the
            // official wallets; extracting the grant to call a public API would
            // defeat that boundary.
            wallets = try await chat.connection.accountAPI.getBalance(client: Self.metadata)
            error = nil
        } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
    }
}

private struct AccountBrowserDestination: Identifiable {
    let id = UUID()
    let url: URL
}
private struct AccountSafari: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
