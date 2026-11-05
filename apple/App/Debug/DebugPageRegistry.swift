// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
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
        "appearance": { AnyView(NavigationStack { AppearanceSettingsPage() }) },
        "language": { AnyView(SettingsView(initial: SettingsLocation("settings", anchor: "language"))) },
        "settings-search": { AnyView(SettingsView(initial: SettingsLocation("search"))) },
        "interface": { AnyView(NavigationStack { InterfaceSettingsPage() }) },
        "voice": { AnyView(NavigationStack { VoiceSettingsPage() }) },
        "performance": { AnyView(NavigationStack { PerformanceSettingsPage() }) },
        "background": { AnyView(NavigationStack { BackgroundSettingsPage() }) },
        "system-access": { AnyView(NavigationStack { SystemAccessPage() }) },
        "help": { AnyView(NavigationStack { HelpSettingsPage() }) },
        "features": { AnyView(NavigationStack { AllSettingsFeaturesPage() }) },
        "web-search": { AnyView(NavigationStack { CapabilitySettingsPage(kind: .search) }) },
        "media": { AnyView(NavigationStack { CapabilitySettingsPage(kind: .media) }) },
        "personalization": { AnyView(NavigationStack { PersonalizationPage() }) },
        "privacy": { AnyView(NavigationStack { PrivacySettingsPage() }) },
        "diagnostics": { AnyView(NavigationStack { DiagnosticsSettingsPage() }) },
        "reply-preferences": { AnyView(NavigationStack { ReplyPreferencesPage() }) },
        "engine-parameters": { AnyView(NavigationStack { EngineParametersPage() }) },
        "schedules": { AnyView(NavigationStack { SchedulesPage() }) },
        "usage": { AnyView(NavigationStack { RunInsightsPage() }) },
        "agents": { AnyView(NavigationStack { AgentPresetsPage() }) },
        "files": { AnyView(NavigationStack { WorkspaceFilesHome() }) },
        "changes": { AnyView(NavigationStack { ChangesPage() }) },
        "workspaces": { AnyView(NavigationStack { WorkspacesPage() }) },
        "capabilities": { AnyView(NavigationStack { CapabilitySettingsPage() }) },
        "account": { AnyView(NavigationStack { DeepSeekAccountPage() }) },
        "providers": { AnyView(NavigationStack { ProviderSettingsPage() }) },
        "model": { AnyView(NavigationStack { ModelSettingsPage() }) },
        "permissions": { AnyView(NavigationStack { PermissionSettingsPage() }) },
        "phone": { AnyView(NavigationStack { PhoneSettingsView() }) },
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
    @Environment(TaskNotifications.self) private var notifications
    @Environment(RelayStore.self) private var relay
    @Environment(\.designTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    let name: String
    let content: AnyView
    var body: some View {
        if let viewport = DebugPageRegistry.viewport {
            let scheme = DebugPageRegistry.captureScheme
            let capturedTypeSize = DebugPageRegistry.argument("-dsh-screen-text") == "large" ? DynamicTypeSize.accessibility2 : typeSize
            DebugPageCapture(name: name, size: viewport, scheme: scheme, content: AnyView(
                content
                    .safeAreaPadding(.top, 32).safeAreaPadding(.bottom, 24)
                    .ignoresSafeArea(.container)
                    .background { AppBackdrop() }
                    .environment(session).environment(engine).environment(hosts)
                    .environment(phone).environment(pet).environment(preferences)
                    .environment(notifications).environment(relay)
                    .environment(\.designTheme, theme)
                    .environment(\.appReduceMotion, true)
                    .environment(\.dynamicTypeSize, capturedTypeSize)
                    .environment(\.colorScheme, scheme)
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
