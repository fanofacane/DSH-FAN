// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/settings/settings_screen.dart (Help), ui/features/all_features_page.dart.
import SwiftUI

struct HelpSettingsPage: View {
    var body: some View {
        SettingsPage(title: "Help") {
            SettingsGroup(header: "Getting started") {
                SettingsLink(glyph: AppIcon.providers, title: "Models") { ProviderSettingsPage() }
                SettingsLink(glyph: AppIcon.engine, title: "Local engine") { EngineView(embedded: true) }
                SettingsLink(glyph: AppIcon.remoteHosts, title: "Remote hosts") { RemoteHostsPage() }
            }
            SettingsGroup(header: "Explore") {
                SettingsLink(glyph: AppIcon.settings, title: "All features") { AllSettingsFeaturesPage() }
                SettingsLink(glyph: AppIcon.diagnostics, title: "Diagnostics") { DiagnosticsSettingsPage() }
            }
        }
    }
}

struct AllSettingsFeaturesPage: View {
    var body: some View {
        SettingsPage(title: "All features") {
            SettingsGroup(header: "Work") {
                SettingsLink(glyph: .folder, title: "Workspaces") { WorkspacesPage() }
                SettingsLink(glyph: .calendar, title: "Scheduled tasks") { SchedulesPage() }
                SettingsLink(glyph: AppIcon.history, title: "Run insights") { RunInsightsPage() }
                SettingsLink(glyph: AppIcon.profile, title: "Agent presets") { AgentPresetsPage() }
            }
            SettingsGroup(header: "Capabilities") {
                SettingsLink(glyph: AppIcon.phoneControl, title: "Phone control") { PhoneSettingsView() }
                SettingsLink(glyph: AppIcon.webSearch, title: "Web search") { CapabilitySettingsPage(kind: .search) }
                SettingsLink(glyph: AppIcon.generateMedia, title: "Images and video") { CapabilitySettingsPage(kind: .media) }
            }
        }
    }
}
