// SPDX-License-Identifier: AGPL-3.0-or-later
// Remote host screens in the Mist Glass style of 原 Flutter 版 lib/ui/remote:
// remote_screen.dart (hosts), ssh_host_form.dart, host_key_dialog.dart,
// host_switcher.dart and host_status.dart.
import DSHRemote
import SwiftUI
import UniformTypeIdentifiers

// MARK: Hosts page

struct RemoteHostsPage: View {
    @Environment(HostStore.self) private var hosts
    @Environment(AppSession.self) private var chat
    @Environment(EngineModel.self) private var engine

    var body: some View {
        @Bindable var hosts = hosts
        SettingsPage(title: "Remote hosts") {
            Text("Keep using DSH from your computer or server on your phone")
                .type(.bodyMedium).foregroundStyle(DS.inkMuted).padding(.horizontal, 8).padding(.bottom, 18)
            if let active = hosts.activeHost {
                SettingsGroup {
                    HostStatusRow(host: active)
                    RowDivider()
                    HStack(spacing: 10) {
                        MistButton(title: "Reconnect", kind: .secondary) { Task { await chat.connection.connect(forceRestart: false) } }
                        MistButton(title: "Use this phone", kind: .secondary) {
                            Task { await chat.switchHost(to: nil, engineRunning: engine.status.phase == .running) }
                        }
                    }
                    .padding(12)
                }
            }
            RelaySection()
            SettingsGroup(header: "SSH hosts", footer: "Host needs SSH enabled and DSH installed") {
                ForEach(hosts.hosts) { host in
                    NavigationLink { SSHHostForm(existing: host) } label: {
                        SettingsRow(glyph: AppIcon.sshHost, title: "", subtitle: host.address, verbatim: host.name) { SettingsChevron() }
                    }
                    .buttonStyle(.plain)
                    RowDivider(inset: 70)
                }
                NavigationLink { SSHHostForm(existing: nil) } label: {
                    SettingsRow(glyph: AppIcon.add, tone: .neutral, title: "Add SSH host", subtitle: String(localized: "No third-party server"))
                }
                .buttonStyle(.plain)
            }
            SettingsGroup(header: "On launch") {
                SettingsToggleRow(title: "Connect to the last host", subtitle: String(localized: "When off, start on this phone"),
                                  isOn: $hosts.autoConnect)
            }
        }
    }
}

/// Active host line: name, address, link state.
struct HostStatusRow: View {
    @Environment(\.designTheme) private var theme
    @Environment(HostStore.self) private var hosts
    let host: ActiveHost

    var body: some View {
        HStack(spacing: 14) {
            Glyph(glyph: host.kind == .relay ? AppIcon.cloud : AppIcon.computer, size: 20).foregroundStyle(theme.onAccentContainer)
                .frame(width: 40, height: 40).background(theme.accentContainer, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Using “\(host.name)”").font(.system(size: 16, weight: .semibold)).foregroundStyle(DS.ink)
                HStack(spacing: 5) {
                    Circle().fill(hosts.state.color).frame(width: 6, height: 6)
                    Text(hosts.state.label(host)).font(.system(size: 13)).foregroundStyle(DS.inkFaint).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

extension HostStore.LinkState {
    var color: Color {
        switch self {
        case .connected: DS.success
        case .failed: DS.danger
        default: DS.warn
        }
    }

    func label(_ host: ActiveHost) -> String {
        switch self {
        case .idle: String(localized: "Connecting")
        case .connecting(let step): host.kind == .relay ? String(localized: "Connecting") : step.title
        case .connected: host.connectedLabel
        case .failed(let title, _): title
        }
    }
}

extension ActiveHost {
    var connectedLabel: String {
        kind == .relay ? String(localized: "Connected · End-to-end encrypted") : String(localized: "Connected · SSH \(detail)")
    }
}

extension LinkStep {
    var title: String {
        switch self {
        case .connecting, .authenticating: String(localized: "Connect to server")
        case .starting: String(localized: "Starting remote DSH…")
        case .forwarding: String(localized: "Create tunnel")
        }
    }
}
