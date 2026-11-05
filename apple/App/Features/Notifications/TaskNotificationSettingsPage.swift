// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/settings/notification_settings.dart.
import ActivityKit
import SwiftUI
import UserNotifications

struct TaskNotificationSettingsPage: View {
    @Environment(TaskNotifications.self) private var notifications
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var askingPermission = false
    @State private var fixtureEnabled: Bool?
    @State private var liveAllowed = true

    private var fixture: String? {
        #if DEBUG
        DebugPageRegistry.usesFixture ? DebugPageRegistry.argument("-dsh-screen-fixture") : nil
        #else
        nil
        #endif
    }
    private var enabled: Bool { fixtureEnabled ?? notifications.enabled }
    private var blocked: Bool { fixture == "blocked" || (fixture == nil && notifications.authorization == .denied) }

    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage(title: "Notifications", subtitle: "Choose which events DSH Fan can notify you about.") {
            if enabled && blocked {
                SettingsGroup(footer: "Allow notifications in iOS Settings to receive alerts.") {
                    Button(action: openSettings) {
                        SettingsRow(glyph: AppIcon.notificationsOff, tone: .danger, title: "System notifications are off")
                    }.buttonStyle(SettingsPressStyle())
                }
            }
            SettingsGroup {
                SettingsToggleRow(title: "Task notifications", subtitle: String(localized: "Notify me when DSH Fan is in the background."),
                                  isOn: Binding(get: { enabled }, set: setEnabled))
                    .disabled(askingPermission).settingAnchor("notifications-enabled")
            }
            SettingsGroup(header: "Alerts", footer: "A suspended app cannot receive new events from remote hosts.") {
                category(.reply, "Reply finished", "When a conversation finishes a reply.", anchor: "notify-done")
                category(.failed, "Error or stopped", "When a conversation fails or stops.", anchor: "notify-failed")
                category(.approval, "Approval needed", "When a command needs permission.", anchor: "notify-approval")
                category(.question, "Question asked", "When AI is waiting for your answer.", anchor: "notify-question")
            }.disabled(!enabled)
            SettingsGroup(header: "Live Activities", footer: "Show conversation progress on the Lock Screen and Dynamic Island.") {
                SettingsToggleRow(title: "Show live progress", subtitle: liveAllowed ? nil : String(localized: "Not allowed"),
                                  isOn: $preferences.showLiveActivity)
                    .disabled(!liveAllowed).settingAnchor("notify-live")
                if !liveAllowed {
                    Button(action: openSettings) { SettingsRow(title: "Open iOS Settings") }
                        .buttonStyle(SettingsPressStyle())
                }
            }
            SettingsGroup(header: "System settings", footer: "Alerts contain no message text, tool arguments or credentials.") {
                Button(action: openSettings) { SettingsRow(title: "Open iOS Settings", value: permissionLabel) }
                    .buttonStyle(SettingsPressStyle()).settingAnchor("notify-system")
                SettingsLink(title: "Background activity") { BackgroundSettingsPage() }
            }
            if let code = notifications.error, fixture == nil {
                Text("Request failed: \(code)").settingsType(.bodySmall).foregroundStyle(DS.danger)
            }
        }
        .task(id: scenePhase) {
            if let fixture { fixtureEnabled = fixture != "off"; return }
            await notifications.refresh()
            liveAllowed = ActivityAuthorizationInfo().areActivitiesEnabled
        }
    }

    private func category(_ kind: TaskNotifications.Kind, _ title: LocalizedStringKey, _ subtitle: String.LocalizationValue, anchor: String) -> some View {
        SettingsToggleRow(title: title, subtitle: String(localized: subtitle), isOn: Binding(
            get: { fixture != nil || notifications.includes(kind) },
            set: { if fixture == nil { notifications.setIncluded($0, for: kind) } }
        )).settingAnchor(anchor)
    }

    private func setEnabled(_ value: Bool) {
        if fixture != nil { fixtureEnabled = value; return }
        if !value { notifications.enabled = false; return }
        if blocked { openSettings(); return }
        guard !askingPermission else { return }
        askingPermission = true
        Task {
            defer { askingPermission = false }
            await notifications.enable()
        }
    }

    private func openSettings() {
        if fixture == nil, let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    private var permissionLabel: String {
        if blocked { return String(localized: "Denied") }
        if fixture != nil { return String(localized: "Allowed") }
        return switch notifications.authorization {
        case .authorized, .provisional, .ephemeral: String(localized: "Allowed")
        case .denied: String(localized: "Denied")
        case .notDetermined: String(localized: "Not requested")
        @unknown default: String(localized: "Unknown")
        }
    }
}
