// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/settings/{interface_page,background_guide_page,performance_page,voice_settings_page,system_access_page}.dart.
import AVFoundation
import EventKit
import Photos
import Speech
import SwiftUI
import UserNotifications

struct InterfaceSettingsPage: View {
    var body: some View {
        SettingsPage(title: "Interface") {
            SettingsGroup(header: "Interface mode",
                          footer: "The iOS app uses the native interface for local and remote conversations.") {
                InfoRow(label: "Interface", value: String(localized: "Native"))
            }
            SettingsGroup(header: "Language", footer: "Close and reopen DSH to apply the language change.") {
                LanguageSettingsRow(tone: .neutral, tinted: false)
            }
            SettingsGroup(header: "Chat") {
                ChatReadingSettingsRows(tone: .neutral, tinted: false)
            }
            QuickPanelSettingsSection()
        }
    }
}

struct PerformanceSettingsPage: View {
    @Environment(AppPreferences.self) private var preferences
    private var systemReduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
    private var systemReduceTransparency: Bool { UIAccessibility.isReduceTransparencyEnabled }

    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage(title: "Performance") {
            SettingsGroup(header: "Effects", footer: "Use fewer visual effects to reduce rendering work on your phone.") {
                SettingsToggleRow(title: "Glass blur", isOn: Binding(
                    get: { preferences.glassBlur && !systemReduceTransparency }, set: { preferences.glassBlur = $0 }
                )).disabled(systemReduceTransparency).settingAnchor("glass-blur")
                SettingsToggleRow(title: "Reduce motion", isOn: Binding(
                    get: { preferences.reduceMotion || systemReduceMotion }, set: { preferences.reduceMotion = $0 }
                )).disabled(systemReduceMotion && !preferences.reduceMotion).settingAnchor("reduce-motion")
            }
        }
    }
}

struct BackgroundSettingsPage: View {
    var body: some View {
        SettingsPage(title: "Background activity") {
            PageHero(title: Text("When you leave DSH Fan"),
                     subtitle: Text("iOS may suspend the app in the background.")) {
                SettingsIcon(glyph: AppIcon.keepAlive, tone: .identity(5), size: 56)
            } trailing: { EmptyView() }

            SettingsGroup(header: "How it works") {
                SettingsRow(glyph: AppIcon.engine, title: "Local engine",
                            subtitle: String(localized: "Keep DSH Fan open while the local engine is working.")) { EmptyView() }
                SettingsRow(glyph: AppIcon.remoteHosts, title: "Remote hosts",
                            subtitle: String(localized: "The host can keep working. DSH Fan reconnects when you return.")) { EmptyView() }
            }
            SettingsGroup(header: "Related settings") {
                SettingsLink(glyph: AppIcon.notifications, title: "Notifications") { TaskNotificationSettingsPage() }
                SettingsLink(glyph: AppIcon.systemAccess, title: "System permissions") { SystemAccessPage() }
            }
        }
    }
}

struct VoiceSettingsPage: View {
    @Environment(AppPreferences.self) private var preferences
    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage(title: "Voice input") {
            SettingsGroup(header: "Dictation", footer: "iOS manages speech recognition and any language data it needs.") {
                SettingsToggleRow(glyph: AppIcon.voice, title: "Voice input", isOn: $preferences.voiceInputEnabled)
                    .settingAnchor("voice-enabled")
            }
            SettingsGroup(header: "System permissions") {
                SettingsLink(glyph: AppIcon.systemAccess, title: "Microphone and speech recognition") { SystemAccessPage() }
            }
        }
    }
}

struct SystemAccessPage: View {
    @Environment(TaskNotifications.self) private var notifications
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var permissions: [Permission] = []

    private struct Permission: Identifiable {
        let title: LocalizedStringKey
        let glyph: DshGlyph
        let state: String
        var id: DshGlyph { glyph }
    }

    var body: some View {
        SettingsPage(title: "System permissions") {
            SettingsGroup(header: "Access on this iPhone",
                          footer: "iOS asks for each permission when you first use its feature. Review or change your choices in Settings.") {
                ForEach(permissions) { permission in
                    SettingsRow(glyph: permission.glyph, title: permission.title, value: permission.state) { EmptyView() }
                }
            }
            MistButton(title: "Open iOS Settings", kind: .secondary) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
        .task(id: scenePhase) { await refresh() }
    }

    private func refresh() async {
        #if DEBUG
        if DebugPageRegistry.usesFixture {
            permissions = snapshot(notifications: "Allowed", calendar: "Write only", reminders: "Not requested",
                                   photos: "Limited access", microphone: "Allowed", speech: "Denied")
            return
        }
        #endif
        await notifications.refresh()
        let notify: String.LocalizationValue
        switch notifications.authorization {
        case .authorized, .provisional, .ephemeral: notify = "Allowed"
        case .notDetermined: notify = "Not requested"
        case .denied: notify = "Denied"
        @unknown default: notify = "Unknown"
        }
        permissions = snapshot(notifications: notify,
                               calendar: eventAccess(.event), reminders: eventAccess(.reminder),
                               photos: photoAccess, microphone: mediaAccess, speech: speechAccess)
    }

    private func snapshot(notifications: String.LocalizationValue, calendar: String.LocalizationValue,
                          reminders: String.LocalizationValue, photos: String.LocalizationValue,
                          microphone: String.LocalizationValue, speech: String.LocalizationValue) -> [Permission] {
        [
            Permission(title: "Notifications", glyph: AppIcon.notifications, state: String(localized: notifications)),
            Permission(title: "Calendar", glyph: .calendar, state: String(localized: calendar)),
            Permission(title: "Reminders", glyph: .listChecks, state: String(localized: reminders)),
            Permission(title: "Photos", glyph: AppIcon.image, state: String(localized: photos)),
            Permission(title: "Microphone", glyph: AppIcon.voice, state: String(localized: microphone)),
            Permission(title: "Speech recognition", glyph: .chatCircle, state: String(localized: speech)),
        ]
    }

    private func eventAccess(_ type: EKEntityType) -> String.LocalizationValue {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: "Allowed"
        case .writeOnly: "Write only"
        case .notDetermined: "Not requested"
        case .denied: "Denied"
        case .restricted: "Restricted"
        @unknown default: "Unknown"
        }
    }

    private var photoAccess: String.LocalizationValue {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: "Allowed"
        case .limited: "Limited access"
        case .notDetermined: "Not requested"
        case .denied: "Denied"
        case .restricted: "Restricted"
        @unknown default: "Unknown"
        }
    }

    private var mediaAccess: String.LocalizationValue {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: "Allowed"
        case .notDetermined: "Not requested"
        case .denied: "Denied"
        case .restricted: "Restricted"
        @unknown default: "Unknown"
        }
    }

    private var speechAccess: String.LocalizationValue {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: "Allowed"
        case .notDetermined: "Not requested"
        case .denied: "Denied"
        case .restricted: "Restricted"
        @unknown default: "Unknown"
        }
    }
}
