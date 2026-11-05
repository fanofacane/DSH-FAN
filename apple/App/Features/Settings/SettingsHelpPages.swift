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
    @Environment(AppSession.self) private var chat
    @Environment(AppPreferences.self) private var preferences
    private var tinted: Bool { preferences.featureIconStyle != "line" }
    var body: some View {
        SettingsPage(title: "All features", subtitle: "Tools for the current chat and this app") {
            SettingsGroup(header: "Current chat") {
                SettingsRow(glyph: AppIcon.profile, title: "Conversation", subtitle: chat.transcript.currentTitle
                            ?? String(localized: "Open a chat to view its features."), tinted: tinted) { EmptyView() }
                SettingsLink(glyph: .sparkle, title: "Skills", tinted: tinted) { FeatureCatalogPage(kind: .skills) }
                SettingsLink(glyph: AppIcon.terminal, title: "Background jobs", tinted: tinted) { FeatureCatalogPage(kind: .jobs) }
            }
            SettingsGroup(header: "Work") {
                SettingsLink(glyph: .folder, title: "Workspaces", tinted: tinted) { WorkspacesPage() }
                SettingsLink(glyph: .calendar, title: "Scheduled tasks", tinted: tinted) { SchedulesPage() }
                SettingsLink(glyph: AppIcon.history, title: "Run insights", tinted: tinted) { RunUsageRoute() }
                SettingsLink(glyph: AppIcon.profile, title: "Agent presets", tinted: tinted) { AgentPresetsPage() }
            }
            SettingsGroup(header: "Capabilities") {
                SettingsLink(glyph: AppIcon.phoneControl, title: "Phone control", tinted: tinted) { PhoneSettingsView() }
                SettingsLink(glyph: AppIcon.webSearch, title: "Web search", tinted: tinted) { CapabilitySettingsPage(kind: .search) }
                SettingsLink(glyph: AppIcon.generateMedia, title: "Images and video", tinted: tinted) { CapabilitySettingsPage(kind: .media) }
            }
        }
    }
}
