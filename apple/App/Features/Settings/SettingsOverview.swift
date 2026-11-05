// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/settings/settings_screen.dart (SettingsOverview),
// ui/account/account_widgets.dart and ui/engine/engine_status.dart.
import DSHClient
import DSHRuntime
import SwiftUI

struct SettingsEngineStatus {
    let phase: RuntimePhase
    var safe = false

    var tone: StatusTone {
        switch phase {
        case .running: safe ? .warn : .ok
        case .starting, .installing, .stopping: .busy
        case .error: .error
        case .installed, .notInstalled: .idle
        }
    }

    var label: String {
        if phase == .running && safe { return String(localized: "Safe mode") }
        if phase == .installed { return String(localized: "Stopped") }
        return String(localized: phase.titleResource)
    }
}

struct SettingsOverview: View {
    let fixture: String?
    let open: (String) -> Void
    @Environment(AppSession.self) private var chat
    @Environment(HostStore.self) private var hosts
    @Environment(EngineModel.self) private var engine
    @State private var account = AccountState()
    @State private var name: String?
    @State private var balance: String?
    @State private var detailError: String?

    private var remote: Bool { fixture == "remote-only" || (fixture == nil && hosts.isRemote) }
    private var signedIn: Bool { fixture == "signed-in" || fixture == "full" || account.status == "credential-stored" }
    private var phase: RuntimePhase { fixture == "remote-only" ? .notInstalled : fixture != nil ? .running : engine.status.phase }
    private var version: String? { fixture == nil ? engine.status.dshVersion : phase == .running ? "0.2.0-rc.2" : nil }
    private var engineStatus: SettingsEngineStatus { SettingsEngineStatus(phase: phase, safe: fixture == nil && engine.safeModeOn) }
    private var destination: String { remote ? "remote" : "account" }

    private var title: String {
        if remote { return fixture == "remote-only" ? "实验室服务器" : hosts.activeHost?.name ?? String(localized: "Remote host") }
        if signedIn { return (fixture != nil ? "雾蓝" : name) ?? String(localized: "DeepSeek account") }
        if chat.connection.keyConfigured { return String(localized: "DeepSeek API key") }
        return String(localized: "Sign in with DeepSeek")
    }

    private var subtitle: String {
        if remote {
            let label = fixture == "remote-only" || hosts.linkAlive ? String(localized: "Connected") : String(localized: "Disconnected")
            return [String(localized: "Remote host"), label].joined(separator: " · ")
        }
        if fixture == "signed-in" || fixture == "full" { return String(localized: "Balance \("¥138.46")") }
        if signedIn {
            if let balance { return String(localized: "Balance \(balance)") }
            return detailError == nil ? String(localized: "Signed in") : String(localized: "Balance unavailable")
        }
        if chat.connection.keyConfigured { return String(localized: "Key configured") }
        return String(localized: "Or enter an API key")
    }

    var body: some View {
        let avatar = DS.identity[fixture == nil ? DS.identityIndex(title) : 1]
        OverviewCard(title: Text(verbatim: title), subtitle: Text(verbatim: subtitle)) {
            if signedIn && !remote {
                Text(String(title.prefix(1))).font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(avatar.ink)
                    .frame(width: 52, height: 52)
                    .background(avatar.fill, in: Circle())
                    .accessibilityHidden(true)
            } else {
                SettingsIcon(glyph: remote ? AppIcon.computer : AppIcon.apiKey, tone: remote ? .identity(6) : .ai, size: 52)
            }
        } accessory: {
            EmptyView()
        } footer: {
            let parts = [String(localized: "Local engine"), engineStatus.label, version.map { "DSH " + $0 }]
            OverviewFooter(tone: engineStatus.tone, text: Text(parts.compactMap { $0 }.joined(separator: " · ")))
        } open: {
            open(destination)
        } openFooter: {
            open("engine")
        }
        .task(id: chat.connection.state == .ready ? chat.connection.generation : -1) { await refresh() }
    }

    private func refresh() async {
        account = AccountState()
        name = nil
        balance = nil
        detailError = nil
        guard fixture == nil, !remote, chat.connection.state == .ready else { return }
        let generation = chat.connection.generation
        do {
            let api = try chat.connection.accountAPI
            let state = try await api.getState()
            guard generation == chat.connection.generation, !Task.isCancelled else { return }
            account = state
            guard state.status == "credential-stored" else { return }
            async let profile = api.getProfile(client: DeepSeekAccountPage.metadata)
            async let wallets = api.getBalance(client: DeepSeekAccountPage.metadata)
            let (profileValue, walletValues) = try await (profile, wallets)
            guard generation == chat.connection.generation, !Task.isCancelled else { return }
            name = profileValue.name
            balance = Self.formatBalance(walletValues)
        } catch {
            // The overview remains usable when a host has no account API or balance is offline.
            guard generation == chat.connection.generation, !Task.isCancelled else { return }
            detailError = (error as? DSHError)?.code ?? "E_TRANSPORT"
        }
    }

    private static func formatBalance(_ wallets: [AccountWallet]) -> String? {
        let groups = Dictionary(grouping: wallets) { $0.currency ?? "" }
        let formatted = groups.keys.sorted().compactMap { currency -> String? in
            guard !currency.isEmpty, let wallets = groups[currency] else { return nil }
            let amounts = wallets.compactMap { $0.balance.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) } }
            guard !amounts.isEmpty else { return nil }
            let format = NumberFormatter()
            format.numberStyle = .currency
            format.currencyCode = currency
            return format.string(from: NSDecimalNumber(decimal: amounts.reduce(0, +)))
        }
        return formatted.isEmpty ? nil : formatted.joined(separator: " · ")
    }
}
