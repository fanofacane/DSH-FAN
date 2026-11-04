// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHRemote
import SwiftUI

// MARK: Host switcher (host_switcher.dart)

struct HostSwitcherSheet: View {
    @Environment(\.designTheme) private var theme
    @Environment(HostStore.self) private var hosts
    @Environment(RelayStore.self) private var relay
    @Environment(AppSession.self) private var chat
    @Environment(EngineModel.self) private var engine
    @Environment(\.dismiss) private var dismiss
    let manage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Switch host").font(.system(size: 18, weight: .semibold)).foregroundStyle(DS.ink)
                .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 10)
            row(glyph: AppIcon.thisPhone, title: String(localized: "This phone"), subtitle: String(localized: "DSH on this phone"),
                active: hosts.activeId == nil) { pick(nil) }
            ForEach(hosts.hosts) { host in
                row(glyph: AppIcon.computer, title: host.name, subtitle: String(localized: "Remote") + " · " + host.address,
                    active: hosts.activeId == host.id) { pick(host.id) }
            }
            ForEach(relay.hosts) { host in
                row(glyph: AppIcon.cloud, title: host.name,
                    subtitle: "DSH Remote · " + (host.online ? String(localized: "Online") : String(localized: "Offline")),
                    active: hosts.activeRelayId == host.id) {
                    hosts.rememberRelayName(host.id, host.name)
                    pick(HostStore.relayId(host.id))
                }
                .disabled(!host.online && hosts.activeRelayId != host.id)
            }
            Text("Connects to one host at a time. Switching disconnects the previous host.")
                .type(.bodySmall).foregroundStyle(DS.inkFaint).padding(.horizontal, 20).padding(.vertical, 8)
            let none = hosts.hosts.isEmpty && relay.hosts.isEmpty
            row(glyph: none ? AppIcon.add : AppIcon.settings,
                title: none ? String(localized: "Connect a computer or server") : String(localized: "Manage remote hosts"),
                subtitle: none ? String(localized: "Via SSH or DSH Remote") : nil, active: false) {
                dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { manage() }
            }
            Spacer(minLength: 0)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .task { if relay.signedIn { await relay.refreshHosts() } }
    }

    private func pick(_ id: String?) {
        dismiss()
        guard id != hosts.activeId else { return }
        Task { await chat.switchHost(to: id, engineRunning: engine.status.phase == .running) }
    }

    private func row(glyph: DshGlyph, title: String, subtitle: String?, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Glyph(glyph: glyph, size: 20).foregroundStyle(active ? theme.onAccentContainer : DS.inkMuted)
                    .frame(width: 40, height: 40).background(active ? theme.accentContainer : DS.surfaceHigh, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).font(.system(size: 16, weight: active ? .semibold : .regular)).foregroundStyle(DS.ink)
                    if let subtitle { Text(verbatim: subtitle).font(.system(size: 13)).foregroundStyle(DS.inkFaint).lineLimit(1) }
                }
                Spacer()
                if active { Glyph(glyph: DshGlyph.check, size: 18).foregroundStyle(theme.accent) }
            }
            .padding(.horizontal, 20).padding(.vertical, 8).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
