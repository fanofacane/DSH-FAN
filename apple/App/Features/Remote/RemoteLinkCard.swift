// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHRemote
import SwiftUI

// MARK: Chat-side link card (host_status.dart / link_progress.dart)

/// Shown in place of the chat while a remote host is connecting or failed.
struct RemoteLinkCard: View {
    @Environment(\.designTheme) private var theme
    @Environment(HostStore.self) private var hosts
    @Environment(AppSession.self) private var chat
    @Environment(EngineModel.self) private var engine
    let host: ActiveHost

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Glyph(glyph: failed ? AppIcon.disconnected : host.kind == .relay ? AppIcon.cloud : AppIcon.computer, size: 22)
                    .foregroundStyle(failed ? DS.danger : theme.onAccentContainer)
                    .frame(width: 46, height: 46).background(failed ? DS.dangerContainer : theme.accentContainer, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: host.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(DS.ink)
                    Text(verbatim: host.detail).font(Mono.font(12, scale: theme.readingScale)).foregroundStyle(DS.inkFaint)
                }
                Spacer()
                if !failed { ProgressView() }
            }
            if !failed, host.kind == .ssh { steps }
            if case .failed(let title, let detail) = hosts.state {
                Text(verbatim: title).type(.bodyMedium).foregroundStyle(DS.danger)
                if let detail, !detail.isEmpty {
                    Text(verbatim: detail).font(Mono.font(12, scale: theme.readingScale)).foregroundStyle(DS.inkMuted).textSelection(.enabled)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.surfaceLow, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
            }
            if failed {
                HStack(spacing: 10) {
                    MistButton(title: "Use this phone", kind: .secondary) {
                        Task { await chat.switchHost(to: nil, engineRunning: engine.status.phase == .running) }
                    }
                    MistButton(title: "Reconnect") { Task { await chat.connection.connect() } }
                }
            }
        }
        .padding(18)
        .glass(.card, radius: Radius.lg)
    }

    private var failed: Bool {
        if case .failed = hosts.state { return true }
        if case .failed = chat.connection.state { return true }
        return false
    }

    private var steps: some View {
        let current: Int = {
            switch hosts.state {
            case .connecting(.connecting), .connecting(.authenticating), .idle: 0
            case .connecting(.starting): 1
            case .connecting(.forwarding): 2
            default: 3
            }
        }()
        let titles: [LocalizedStringKey] = ["Connect to server", "Start DSH", "Create tunnel", "Connecting"]
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(titles.indices, id: \.self) { index in
                HStack(spacing: 10) {
                    Circle().fill(index < current ? DS.success : index == current ? theme.accent : DS.rule).frame(width: 8, height: 8)
                    Text(titles[index]).font(.system(size: 14))
                        .foregroundStyle(index <= current ? DS.ink : DS.inkFaint)
                }
            }
        }
    }
}
