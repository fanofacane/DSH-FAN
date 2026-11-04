// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Remote screens in the Mist Glass style of 原 Flutter 版 lib/ui/remote
// (remote_screen.dart _RelaySection, relay_login_sheet.dart, relay_credit.dart).
import DSHRemote
import SwiftUI

/// The DSH Remote group on the remote hosts page.
struct RelaySection: View {
    @Environment(\.designTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(RelayStore.self) private var relay
    @Environment(HostStore.self) private var hosts
    @Environment(AppSession.self) private var chat
    @Environment(EngineModel.self) private var engine
    @State private var showEmailLogin = false
    @State private var confirmSignOut = false

    var body: some View {
        Group {
            if relay.signedIn { signedIn } else { signedOut }
            Text(relay.serverText.isEmpty
                 ? String(localized: "Service by \("ds-harness-remote")")
                 : String(localized: "Service by \("ds-harness-remote") · Current server: \(relay.serverText)"))
                .type(.bodySmall).foregroundStyle(DS.inkFaint).padding(.horizontal, 8).padding(.top, -12).padding(.bottom, 22)
        }
        .sheet(isPresented: $showEmailLogin) { RelayLoginSheet() }
        .alert("Sign out of DSH Remote?", isPresented: $confirmSignOut) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) {
                Task {
                    if hosts.activeRelayId != nil { await chat.switchHost(to: nil, engineRunning: engine.status.phase == .running) }
                    await relay.signOut()
                }
            }
        } message: {
            Text("This phone will be removed from your account. DSH and chats on the host stay. You can sign in again anytime.")
        }
        .task { if relay.signedIn { await relay.refreshHosts() } else { await relay.loadProviders() } }
    }

    private var signedOut: some View {
        SettingsGroup(header: "DSH Remote") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Glyph(glyph: AppIcon.cloud, size: 22).foregroundStyle(theme.onAccentContainer)
                        .frame(width: 44, height: 44).background(theme.accentContainer, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sign in to DSH Remote").font(.system(size: 16, weight: .semibold)).foregroundStyle(DS.ink)
                        Text("No network setup. End-to-end encrypted connection.").type(.bodySmall).foregroundStyle(DS.inkMuted)
                    }
                }
                if let pending = relay.pendingLogin {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Finish signing in in your browser…").type(.bodyMedium).foregroundStyle(DS.inkMuted)
                        Spacer()
                        Button("Cancel") { relay.cancelBrowserSignIn() }.font(.system(size: 14, weight: .semibold))
                    }
                    Button { Task { openURL(pending.scanURL) } } label: {
                        Text("Reopen browser").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.accent)
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(relay.providers) { provider in
                        MistButton(title: "Continue with \(provider.displayName)") {
                            Task { await relay.signInWithBrowser(provider) }
                        }
                    }
                    MistButton(title: "Self-hosted server · Email sign-in", kind: relay.providers.isEmpty ? .primary : .secondary) {
                        showEmailLogin = true
                    }
                }
                if let error = relay.signInError {
                    Text(verbatim: error).type(.bodySmall).foregroundStyle(DS.danger)
                }
            }
            .padding(16)
        }
    }

    private var signedIn: some View {
        SettingsGroup(header: "DSH Remote", footer: "Install the remote plugin in the host’s DSH and sign in") {
            SettingsRow(glyph: AppIcon.cloud, title: "", subtitle: relay.serverText, verbatim: relay.user?.account ?? "") {
                Button("Sign out") { confirmSignOut = true }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(DS.danger)
            }
            if relay.hosts.isEmpty {
                RowDivider(inset: 70)
                Button { Task { await relay.refreshHosts() } } label: {
                    SettingsRow(title: LocalizedStringKey(relay.hostsError ?? String(localized: "No hosts yet")),
                                subtitle: relay.loadingHosts ? String(localized: "Loading") : nil) {
                        Glyph(glyph: AppIcon.reconnecting, size: 18).foregroundStyle(DS.inkFaint)
                    }
                }
                .buttonStyle(.plain)
            }
            ForEach(relay.hosts) { host in
                RowDivider(inset: 70)
                Button { use(host) } label: { RelayHostRow(host: host, active: hosts.activeRelayId == host.id) }
                    .buttonStyle(.plain)
                    .disabled(!host.online && hosts.activeRelayId != host.id)
            }
        }
    }

    private func use(_ host: RemoteHostInfo) {
        hosts.rememberRelayName(host.id, host.name)
        let id = HostStore.relayId(host.id)
        Task {
            if hosts.activeId == id { await chat.connection.connect() } else {
                await chat.switchHost(to: id, engineRunning: engine.status.phase == .running)
            }
        }
    }
}

struct RelayHostRow: View {
    @Environment(\.designTheme) private var theme
    let host: RemoteHostInfo
    let active: Bool

    var body: some View {
        SettingsRow(glyph: AppIcon.computer, tone: host.online ? .ai : .neutral, title: "", subtitle: subtitle, verbatim: host.name) {
            if active { Glyph(glyph: DshGlyph.check, size: 18).foregroundStyle(theme.accent) }
            else {
                Circle().fill(host.online ? DS.success : DS.rule).frame(width: 8, height: 8)
            }
        }
    }

    private var subtitle: String {
        var parts = [host.online ? String(localized: "Online") : String(localized: "Offline")]
        if !host.platform.isEmpty { parts.append(host.platform) }
        if host.trust == .keyChanged { parts.append(String(localized: "Host identity key has changed")) }
        return parts.joined(separator: " · ")
    }
}

/// Email and password sign-in for a self-hosted Server (relay_login_sheet.dart).
struct RelayLoginSheet: View {
    @Environment(RelayStore.self) private var relay
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Self-hosted server").font(.system(size: 20, weight: .semibold)).foregroundStyle(DS.ink)
            Text("Sign in to your own liguobao/ds-harness-remote with email and password")
                .type(.bodyMedium).foregroundStyle(DS.inkMuted)
            field("Server address", text: $server, keyboard: .URL)
            field("Email", text: $email, keyboard: .emailAddress)
            VStack(alignment: .leading, spacing: 4) {
                Text("Password").font(.system(size: 13)).foregroundStyle(DS.inkFaint)
                SecureField("", text: $password)
                    .padding(.horizontal, 14).frame(height: 46)
                    .background(DS.surfaceLow, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            if let message = error ?? relay.signInError {
                Text(verbatim: message).type(.bodySmall).foregroundStyle(DS.danger)
            }
            MistButton(title: "Sign in", busy: relay.signingIn) { Task { await submit() } }
            Spacer(minLength: 0)
        }
        .padding(22)
        .presentationDetents([.large])
        .presentationBackground(.ultraThinMaterial)
        .onAppear { server = relay.serverText }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13)).foregroundStyle(DS.inkFaint)
            TextField("", text: text)
                .keyboardType(keyboard).autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(.horizontal, 14).frame(height: 46)
                .background(DS.surfaceLow, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private func submit() async {
        error = nil
        guard !server.trimmingCharacters(in: .whitespaces).isEmpty, !email.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
            error = String(localized: "Enter the server address, email and password"); return
        }
        guard relay.setServer(server) else { error = String(localized: "Invalid server address"); return }
        if await relay.signIn(email: email, password: password) { dismiss() }
    }
}
