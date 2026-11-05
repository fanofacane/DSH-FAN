// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/settings/personalization_page.dart.
import SwiftUI

struct PersonalizationPage: View {
    @Environment(HostStore.self) private var hosts
    @Environment(EngineModel.self) private var engine
    @State private var summary: String?
    #if DEBUG
    @State private var exampleVisualReplies = true
    #endif

    var body: some View {
        SettingsPage(title: "Personalization") {
            if !hosts.isRemote {
                SettingsGroup(header: "About you") {
                    SettingsLink(title: "Reply preferences", subtitle: summary ?? String(localized: "Not set")) {
                        ReplyPreferencesPage()
                    }
                }
            }
            #if DEBUG
            if DebugPageRegistry.usesFixture {
                SettingsGroup(header: "Replies") {
                    SettingsToggleRow(title: "Visual replies", subtitle: String(localized: "Charts, comparisons and tappable options"),
                                      isOn: $exampleVisualReplies)
                }
            }
            #endif
            SettingsGroup(header: "Working style") {
                SettingsLink(title: "Agent presets") { AgentPresetsPage() }
            }
        }
        .task(id: engine.status.phase) {
            #if DEBUG
            if DebugPageRegistry.usesFixture { summary = "回答简洁，先给结论。"; return }
            #endif
            guard !hosts.isRemote, engine.status.phase == .running else { summary = nil; return }
            summary = (try? await engine.runtime.replyPreferences())?
                .split(whereSeparator: \.isNewline).first.map(String.init)
        }
    }
}
