// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import DSHClient
import SwiftUI

@MainActor enum DebugPageRegistry {
    nonisolated static func argument(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
    static var requestedName: String? { argument("-dsh-screen") }
    static var scrollOffset: CGFloat? {
        guard let raw = argument("-dsh-screen-scroll"), let offset = Double(raw), offset.isFinite else { return nil }
        return CGFloat(max(0, offset))
    }
    static var viewport: CGSize? {
        guard usesFixture, let raw = argument("-dsh-screen-size") else { return nil }
        let parts = raw.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, (260...1024).contains(parts[0]), (240...4000).contains(parts[1]) else { return nil }
        return CGSize(width: parts[0], height: parts[1])
    }
    static var usesFixture: Bool { requestedName != nil && argument("-dsh-screen-fixture") != nil }
    static var captureScheme: ColorScheme {
        argument("-dsh-screen-appearance") == "dark" ? .dark : .light
    }
    static let pages: [String: @MainActor () -> AnyView] = [
        "chat": { AnyView(ChatView()) },
        "drawer": { AnyView(ChatView(drawerOpen: true)) },
        "settings": { AnyView(SettingsView()) },
        "notifications": { AnyView(NavigationStack { TaskNotificationSettingsPage() }) },
        "app-icon-picker": { AnyView(SettingsGroup { AlternateIconPicker() }.padding(.horizontal, Space.lg)) },
        "launch-section": { AnyView(SettingsGroup { AppearanceImageSection(kind: .launch) }.padding(.horizontal, Space.lg)) },
        "wallpaper-section": { AnyView(SettingsGroup { AppearanceImageSection(kind: .wallpaper) }.padding(.horizontal, Space.lg)) },
        "wallpaper-editor": { AnyView(NavigationStack { WallpaperEditorPage() }) },
        "wallpaper-preview": { AnyView(WallpaperPreviewPage()) },
        "diagnostics-export": { AnyView(DiagnosticReviewSheet(snapshot: "[system] Engine is running.")) },
        "licenses": { AnyView(NavigationStack { OpenSourceLicensesPage() }) },
        "appearance": { AnyView(NavigationStack { AppearanceSettingsPage() }) },
        "language": { AnyView(SettingsView(initial: SettingsLocation("settings", anchor: "language"))) },
        "settings-search": { AnyView(SettingsView(initial: SettingsLocation("search"))) },
        "interface": { AnyView(NavigationStack { InterfaceSettingsPage() }) },
        "voice": { AnyView(NavigationStack { VoiceSettingsPage() }) },
        "performance": { AnyView(NavigationStack { PerformanceSettingsPage() }) },
        "background": { AnyView(NavigationStack { BackgroundSettingsPage() }) },
        "system-access": { AnyView(NavigationStack { SystemAccessPage() }) },
        "help": { AnyView(NavigationStack { HelpSettingsPage() }) },
        "skills": { AnyView(NavigationStack { FeatureCatalogPage(kind: .skills) }) },
        "jobs": { AnyView(NavigationStack { FeatureCatalogPage(kind: .jobs) }) },
        "features": { AnyView(NavigationStack { AllSettingsFeaturesPage() }) },
        "web-search": { AnyView(NavigationStack { CapabilitySettingsPage(kind: .search) }) },
        "media": { AnyView(NavigationStack { CapabilitySettingsPage(kind: .media) }) },
        "personalization": { AnyView(NavigationStack { PersonalizationPage() }) },
        "privacy": { AnyView(NavigationStack { PrivacySettingsPage() }) },
        "diagnostics": { AnyView(NavigationStack { DiagnosticsSettingsPage() }) },
        "reply-preferences": { AnyView(NavigationStack { ReplyPreferencesPage() }) },
        "engine-shell": { AnyView(NavigationStack { EngineNamespacePage(id: .shell) }) },
        "engine-agent-loop": { AnyView(NavigationStack { EngineNamespacePage(id: .agentLoop) }) },
        "engine-subagent": { AnyView(NavigationStack { EngineNamespacePage(id: .subagent) }) },
        "engine-general": { AnyView(NavigationStack { EngineNamespacePage(id: .general) }) },
        "engine-number": {
            let section = DebugEngineSettings.sections.first { $0.id == "bash-sandbox" }
            return AnyView(Group {
                if let section, let node = EngineSchema(section.schema).fields(section.schema)["timeoutMs"] {
                    EngineFieldEditor(model: EngineFormModel(section), path: ["timeoutMs"], node: node)
                }
            })
        },
        "engine-parameters": { AnyView(NavigationStack { EngineParametersPage() }) },
        "schedules": { AnyView(NavigationStack { SchedulesPage() }) },
        "usage": { AnyView(NavigationStack { RunInsightsPage() }) },
        "agent-preset": { AnyView(NavigationStack {
            AgentPresetPage(preset: AgentPreset(id: "default", name: "Standard agent", isDefault: true),
                            defaults: nil, generation: 0, onChange: {})
        }) },
        "agents": { AnyView(NavigationStack { AgentPresetsPage() }) },
        "files": { AnyView(NavigationStack { WorkspaceFilesHome() }) },
        "changes": { AnyView(NavigationStack { ChangesPage() }) },
        "workspaces": { AnyView(NavigationStack { WorkspacesPage() }) },
        "capabilities": { AnyView(NavigationStack { CapabilitySettingsPage() }) },
        "account": { AnyView(NavigationStack { DeepSeekAccountPage() }) },
        "provider-detail": { AnyView(NavigationStack {
            ProviderDetailPage(provider: DebugProviderSettings.example, namespaces: DebugProviderSettings.sections, onSave: {})
        }) },
        "provider-form": { AnyView(NavigationStack {
            ProviderEditor(provider: DebugProviderSettings.example, sections: DebugProviderSettings.sections)
        }) },
        "provider-model": { AnyView(ProviderModelEditor(original: ["id": "example/model", "name": "Example model",
                                                                  "contextWindow": 131_072, "maxTokens": 8192],
                                                        reservedIDs: [], apply: { _ in })) },
        "providers": { AnyView(NavigationStack { ProviderSettingsPage() }) },
        "model": { AnyView(NavigationStack { ModelSettingsPage() }) },
        "permissions": { AnyView(NavigationStack { PermissionSettingsPage() }) },
        "phone-confirm": { AnyView(NavigationStack { PhoneConfirmModePage() }) },
        "phone-rules": { AnyView(NavigationStack { PhoneRulesPage() }) },
        "phone-actions": { AnyView(NavigationStack { PhoneActionLogPage() }) },
        "phone-disclosure": { AnyView(PhoneDisclosureSheet {}) },
        "safe-mode": {
            AnyView(NavigationStack {
                SettingsPage(title: "Safe mode") {
                    if let status = DebugEngineSettings.status {
                        SettingsGroup { SafeModeSettingsRows(status: status) }.disabled(true)
                    }
                }
            })
        },
        "phone": { AnyView(NavigationStack { PhoneSettingsView() }) },
        "pet-preview": { AnyView(DebugPetPage()) },
        "pet-overlay": { AnyView(AppBackdrop().overlay(alignment: .top) { PetOutsideSection().padding(Space.lg) }) },
        "pet": { AnyView(NavigationStack { PetSettingsPage() }) },
        "about": { AnyView(NavigationStack { AboutPage() }) },
        "engine": { AnyView(EngineView()) },
        "key": { AnyView(NavigationStack { KeySettingsPage() }) },
        "remote": { AnyView(NavigationStack { RemoteHostsPage() }) },
        "welcome": { AnyView(OnboardingView {}) },
        "setup": { AnyView(EnginePreparingView()) },
    ]
    static func page(_ name: String) -> AnyView {
        AnyView(DebugScreenshotPage(name: name, content: pages[name]?() ?? AnyView(EnginePreparingView())))
    }
}

/// A port can accept connections before the model catalog is ready for a screenshot.
private struct DebugScreenshotPage: View {
    @Environment(AppSession.self) private var session
    @Environment(EngineModel.self) private var engine
    @Environment(HostStore.self) private var hosts
    @Environment(PhoneController.self) private var phone
    @Environment(PetModel.self) private var pet
    @Environment(AppPreferences.self) private var preferences
    @Environment(AppearanceImages.self) private var images
    @Environment(AlternateIconController.self) private var icons
    @Environment(TaskNotifications.self) private var notifications
    @Environment(RelayStore.self) private var relay
    @Environment(\.designTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    let name: String
    let content: AnyView
    var body: some View {
        if let viewport = DebugPageRegistry.viewport {
            let scheme = DebugPageRegistry.captureScheme
            let safeInsets = DebugPageRegistry.argument("-dsh-screen-safe") != "none"
            let capturedTypeSize = DebugPageRegistry.argument("-dsh-screen-text") == "large" ? DynamicTypeSize.accessibility2 : typeSize
            DebugPageCapture(name: name, size: viewport, scheme: scheme, content: AnyView(
                content
                    .safeAreaPadding(.top, safeInsets ? 32 : 0).safeAreaPadding(.bottom, safeInsets ? 24 : 0)
                    .ignoresSafeArea(.container)
                    .background { AppBackdrop() }
                    .environment(session).environment(engine).environment(hosts)
                    .environment(phone).environment(pet).environment(preferences)
                    .environment(notifications).environment(relay)
                    .environment(images).environment(icons)
                    .environment(\.designTheme, theme)
                    .environment(\.appReduceMotion, true)
                    .environment(\.dynamicTypeSize, capturedTypeSize)
                    .environment(\.colorScheme, scheme)
                    .environment(\.displayScale, 2)
            ))
            .ignoresSafeArea()
        } else {
            livePage
        }
    }

    private var livePage: some View {
        content.task {
            while !Task.isCancelled {
                if DebugPageRegistry.usesFixture || session.connection.state == .ready {
                    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("screen-ready.txt")
                    try? Data(name.utf8).write(to: url, options: .atomic)
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
}
#endif
