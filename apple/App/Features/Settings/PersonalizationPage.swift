// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/settings/personalization_page.dart.
import SwiftUI

struct PersonalizationPage: View {
    @Environment(HostStore.self) private var hosts
    @Environment(EngineModel.self) private var engine
    @Environment(AppPreferences.self) private var preferences
    @State private var summary: String?

    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage(title: "Personalization") {
            if !hosts.isRemote {
                SettingsGroup(header: "About you") {
                    SettingsLink(title: "Personal preferences", subtitle: summary ?? String(localized: "Not set")) {
                        ReplyPreferencesPage()
                    }
                }
            }
            if !hosts.isRemote {
                SettingsGroup(header: "Replies") {
                    SettingsToggleRow(title: "Visual replies", subtitle: String(localized: "Charts, comparisons and tappable options"),
                                      isOn: $preferences.visualReplies).settingAnchor("visual-replies")
                }
            }
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
