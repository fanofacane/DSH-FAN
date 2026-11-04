// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import SwiftUI

@MainActor enum DebugPageRegistry {
    static var requestedName: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-dsh-screen"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
    static let pages: [String: @MainActor () -> AnyView] = [
        "chat": { AnyView(ChatView()) },
        "drawer": { AnyView(ChatView(drawerOpen: true)) },
        "settings": { AnyView(SettingsView()) },
        "notifications": { AnyView(NavigationStack { TaskNotificationSettingsPage() }) },
        "appearance": { AnyView(NavigationStack { AppearanceSettingsPage() }) },
        "language": { AnyView(NavigationStack { LanguageSettingsPage() }) },
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
    let name: String
    let content: AnyView
    var body: some View {
        content.task {
            while !Task.isCancelled {
                if session.connection.state == .ready {
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
