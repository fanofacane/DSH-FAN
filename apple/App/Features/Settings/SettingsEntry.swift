// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct SettingsContext {
    var isRemote = false
    var modelSubtitle: String?
    var presetName: String?
    var remoteSubtitle: String?
    var phoneEnabled = false
    var petEnabled = false
    var version: String?
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case header, ai = "AI", connection = "Connection", abilities = "Abilities", about = "About"
    var id: String { rawValue }
}

@MainActor struct SettingsEntry: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let glyph: DshGlyph?
    let tone: TileTone
    let group: SettingsSection
    let order: Int
    let localOnly: Bool
    let dividerInset: CGFloat
    let subtitle: (SettingsContext) -> String?
    let destination: () -> AnyView

    init<Destination: View>(_ id: String, title: LocalizedStringKey, glyph: DshGlyph? = nil, tone: TileTone = .ai,
                           group: SettingsSection, order: Int, localOnly: Bool = false, dividerInset: CGFloat = 16,
                           subtitle: @escaping (SettingsContext) -> String? = { _ in nil },
                           @ViewBuilder destination: @escaping () -> Destination) {
        self.id = id; self.title = title; self.glyph = glyph; self.tone = tone
        self.group = group; self.order = order; self.localOnly = localOnly; self.dividerInset = dividerInset
        self.subtitle = subtitle; self.destination = { AnyView(destination()) }
    }
}

@MainActor enum SettingsRegistry {
    static let key = SettingsEntry("key", title: "API key", glyph: AppIcon.apiKey, group: .header, order: 0) { KeySettingsPage() }
    static let engine = SettingsEntry("engine", title: "Local engine", group: .header, order: 1) { EngineView(embedded: true) }
    static let entries: [SettingsEntry] = [
        key, engine,
        SettingsEntry("reply-preferences", title: "Reply preferences", group: .ai, order: 0) { ReplyPreferencesPage() },
        SettingsEntry("agents", title: "Agent presets", group: .ai, order: 1) { AgentPresetsPage() },
        SettingsEntry("account", title: "DeepSeek account", group: .ai, order: 2, localOnly: true) { DeepSeekAccountPage() },
        SettingsEntry("providers", title: "Model providers", group: .ai, order: 3) { ProviderSettingsPage() },
        SettingsEntry("model", title: "Model", glyph: AppIcon.model, group: .ai, order: 4, dividerInset: 70, subtitle: { $0.modelSubtitle }) { ModelSettingsPage() },
        SettingsEntry("permissions", title: "Permissions", glyph: AppIcon.permissions, group: .ai, order: 5, subtitle: { $0.presetName }) { PermissionSettingsPage() },
        SettingsEntry("workspaces", title: "Workspaces", group: .connection, order: 0) { WorkspacesPage() },
        SettingsEntry("remote", title: "Remote hosts", glyph: AppIcon.remoteHosts, group: .connection, order: 1, subtitle: { $0.remoteSubtitle }) { RemoteHostsPage() },
        SettingsEntry("notifications", title: "Notifications and background", group: .abilities, order: 0) { TaskNotificationSettingsPage() },
        SettingsEntry("schedules", title: "Scheduled tasks", group: .abilities, order: 1) { SchedulesPage() },
        SettingsEntry("capabilities", title: "Search, images and video", group: .abilities, order: 2) { CapabilitySettingsPage() },
        SettingsEntry("phone", title: "Phone control", glyph: AppIcon.phoneControl, tone: .ability, group: .abilities, order: 3, dividerInset: 70, subtitle: { $0.phoneEnabled ? String(localized: "On") : String(localized: "Off") }) { PhoneSettingsView() },
        SettingsEntry("pet", title: "Pet", glyph: AppIcon.pet, tone: .ability, group: .abilities, order: 4, subtitle: { $0.petEnabled ? String(localized: "Deepy the whale") : String(localized: "Off") }) { PetSettingsPage() },
        SettingsEntry("appearance", title: "Interface", group: .about, order: 0) { AppearanceSettingsPage() },
        SettingsEntry("language", title: "Language", group: .about, order: 1) { LanguageSettingsPage() },
        SettingsEntry("privacy", title: "Privacy", group: .about, order: 2) { PrivacySettingsPage() },
        SettingsEntry("diagnostics", title: "Diagnostics", group: .about, order: 3) { DiagnosticsSettingsPage() },
        SettingsEntry("engine-parameters", title: "Engine parameters", group: .about, order: 4) { EngineParametersPage() },
        SettingsEntry("about", title: "About DSH", glyph: AppIcon.info, tone: .neutral, group: .about, order: 5, subtitle: { $0.version }) { AboutPage() },
    ]
    static func destination(_ id: String) -> AnyView { entries.first { $0.id == id }?.destination() ?? AnyView(EmptyView()) }
    static var sections: [SettingsSection] { SettingsSection.allCases.filter { $0 != .header } }
    static func entries(in group: SettingsSection, context: SettingsContext) -> [SettingsEntry] {
        entries.filter { $0.group == group && (!$0.localOnly || !context.isRemote) }
            .sorted { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order }
    }
}
