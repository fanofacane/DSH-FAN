// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHRemote
import SwiftUI

// MARK: Host key trust (host_key_dialog.dart)

struct HostKeySheet: View {
    @Environment(\.designTheme) private var theme
    @Environment(HostStore.self) private var hosts
    let prompt: HostKeyPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Glyph(glyph: AppIcon.fingerprint, size: 24).foregroundStyle(theme.onAccentContainer)
                    .frame(width: 48, height: 48).background(theme.accentContainer, in: Circle())
                Text("Trust this host?").font(.system(size: 20, weight: .semibold)).foregroundStyle(DS.ink)
            }
            Group {
                if prompt.kind == .relay {
                    Text("First connection to “\(prompt.hostName)”. Check that the identity fingerprint matches the one shown by the host’s remote plugin before continuing.")
                } else {
                    Text("First connection to “\(prompt.hostName)” (\(prompt.address)). Check the fingerprint to confirm it’s your host.")
                }
            }
            .type(.bodyMedium).foregroundStyle(DS.inkMuted)
            VStack(alignment: .leading, spacing: 6) {
                Text(prompt.key.type).font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.inkFaint)
                Text(prompt.key.fingerprint).font(Mono.font(13, scale: theme.readingScale)).foregroundStyle(DS.ink).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.surfaceLow, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            if prompt.kind == .ssh {
                Text("Run \("ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub") on that host to see the same fingerprint. DSH will refuse to connect if it changes.")
                    .type(.bodySmall).foregroundStyle(DS.inkFaint)
            } else {
                Text("DSH will refuse to connect if the fingerprint changes.").type(.bodySmall).foregroundStyle(DS.inkFaint)
            }
            HStack(spacing: 10) {
                MistButton(title: "Cancel", kind: .secondary) { hosts.answerHostKey(false) }
                MistButton(title: "Trust and connect") { hosts.answerHostKey(true) }
            }
        }
        .padding(22)
        .presentationDetents([.large])
        .presentationBackground(.ultraThinMaterial)
        .interactiveDismissDisabled()
    }
}
