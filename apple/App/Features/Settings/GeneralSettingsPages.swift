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

enum PerformanceMode: String, CaseIterable {
    case auto, full, light

    var isLightweight: Bool {
        switch self {
        case .auto:
            let system = ProcessInfo.processInfo
            return system.isLowPowerModeEnabled || system.thermalState == .serious || system.thermalState == .critical
        case .full: return false
        case .light: return true
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .auto: "Automatic"
        case .full: "Full"
        case .light: "Lightweight"
        }
    }

    var summary: String {
        switch self {
        case .auto: String(localized: "Adjusts effects when iOS reports low power or high temperature.")
        case .full: String(localized: "Keeps glass and motion effects enabled.")
        case .light: String(localized: "Uses less blur and motion.")
        }
    }
}

struct PerformanceSettingsPage: View {
    @Environment(AppPreferences.self) private var preferences
    @State private var lightweight = false

    private var systemReduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
    private var systemReduceTransparency: Bool { UIAccessibility.isReduceTransparencyEnabled }
    private var blur: Bool { preferences.useModeEffects ? !lightweight : preferences.glassBlur }
    private var motion: Bool { preferences.useModeEffects ? !lightweight : !preferences.reduceMotion }

    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage(title: "Performance") {
            SettingsGroup(footer: "Choose how many visual effects DSH Fan uses.") {
                ForEach(PerformanceMode.allCases, id: \.self) { mode in
                    Button {
                        preferences.performanceMode = mode
                        lightweight = mode.isLightweight
                    } label: {
                        SettingsRow(title: mode.title, subtitle: mode.summary) {
                            Image(systemName: preferences.performanceMode == mode ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 22)).frame(width: 32).foregroundStyle(DS.inkMuted)
                        }
                    }.buttonStyle(SettingsPressStyle())
                        .accessibilityAddTraits(preferences.performanceMode == mode ? .isSelected : [])
                }
            }.settingAnchor("performance-mode")
            SettingsGroup(footer: "iOS manages the display refresh rate.") {
                InfoRow(label: "Display refresh rate", value: String(localized: "System"))
            }
            SettingsGroup(header: "Effects") {
                SettingsToggleRow(title: "Glass blur", isOn: Binding(
                    get: { blur && !systemReduceTransparency }, set: { value in
                        preserveEffects()
                        preferences.glassBlur = value
                    }
                )).disabled(systemReduceTransparency).settingAnchor("glass-blur")
                SettingsToggleRow(title: "Animations", subtitle: String(localized: "Respects Reduce Motion in iOS Settings."),
                                  isOn: Binding(get: { motion && !systemReduceMotion }, set: { value in
                    preserveEffects()
                    preferences.reduceMotion = !value
                })).disabled(systemReduceMotion).settingAnchor("reduce-motion")
                if motion && !systemReduceMotion {
                    SettingsToggleRow(title: "Fluid motion", subtitle: String(localized: "Adds spring motion to buttons and segments."),
                                      isOn: $preferences.fluidMotion)
                }
                if !preferences.useModeEffects {
                    Button { preferences.useModeEffects = true } label: {
                        SettingsRow(title: "Follow performance mode") { EmptyView() }
                    }.buttonStyle(SettingsPressStyle())
                }
            }
        }
        .onAppear {
            #if DEBUG
            if DebugPageRegistry.argument("-dsh-screen-fixture") == "lightweight" { preferences.performanceMode = .light }
            #endif
            lightweight = preferences.performanceMode.isLightweight
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            lightweight = preferences.performanceMode.isLightweight
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lightweight = preferences.performanceMode.isLightweight
        }
    }

    private func preserveEffects() {
        guard preferences.useModeEffects else { return }
        preferences.glassBlur = blur
        preferences.reduceMotion = !motion
        preferences.useModeEffects = false
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
    @State private var showLanguages = false

    private var locale: Locale { preferences.voiceLocale == "system" ? .current : Locale(identifier: preferences.voiceLocale) }
    private var language: String { Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier }
    private var offlineStatus: String {
        #if DEBUG
        if let fixture = DebugPageRegistry.usesFixture ? DebugPageRegistry.argument("-dsh-screen-fixture") : nil {
            return String(localized: fixture == "ready" ? "Available on this device" : "Managed by iOS")
        }
        #endif
        return String(localized: SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition == true
                      ? "Available on this device" : "Managed by iOS")
    }

    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage(title: "Voice input", subtitle: "Dictate a message using iOS speech recognition.") {
            SettingsGroup {
                SettingsToggleRow(glyph: AppIcon.voice, title: "Voice input", isOn: $preferences.voiceInputEnabled)
                    .settingAnchor("voice-enabled")
            }
            SettingsGroup(header: "Recognition",
                          footer: "iOS manages the speech model. Network recognition may use Apple’s speech service.") {
                Button { showLanguages = true } label: {
                    SettingsRow(title: "Speech recognition language", value: language)
                }.buttonStyle(SettingsPressStyle()).settingAnchor("voice-language")
                InfoRow(label: "On-device model", value: offlineStatus)
                SettingsToggleRow(title: "On-device recognition only", isOn: $preferences.voiceOfflineOnly)
                    .settingAnchor("voice-offline")
            }
            .disabled(!preferences.voiceInputEnabled)
            SettingsGroup(header: "System permissions") {
                SettingsLink(glyph: AppIcon.systemAccess, title: "Microphone and speech recognition") { SystemAccessPage() }
            }
        }
        .sheet(isPresented: $showLanguages) {
            SettingsSheet(title: "Speech recognition language", locked: true) {
                ScrollView {
                    SheetGroup {
                        SettingsChoiceRow(title: String(localized: "Follow system"), selected: preferences.voiceLocale == "system") {
                            preferences.voiceLocale = "system"; showLanguages = false
                        }
                        ForEach(SFSpeechRecognizer.supportedLocales().map(\.identifier).sorted(), id: \.self) { id in
                            SettingsChoiceRow(title: Locale.current.localizedString(forIdentifier: id) ?? id,
                                              selected: preferences.voiceLocale == id) {
                                preferences.voiceLocale = id; showLanguages = false
                            }
                        }
                    }
                }
            }.presentationDetents([.medium, .large])
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
        SettingsPage(title: "System permissions", subtitle: "Permissions used by each feature.") {
            SettingsGroup(header: "Notifications",
                          footer: "iOS asks for each permission when you first use its feature. Review or change your choices in Settings.") {
                permissionRows([AppIcon.notifications])
            }
            SettingsGroup(header: "Phone control") {
                permissionRows([.calendar, .listChecks, AppIcon.image])
            }
            SettingsGroup(header: "Voice input") {
                permissionRows([AppIcon.voice, .chatCircle])
            }
            MistButton(title: "Open iOS Settings", kind: .secondary) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
        .task(id: scenePhase) { await refresh() }
    }

    private func permissionRows(_ glyphs: [DshGlyph]) -> some View {
        ForEach(permissions.filter { glyphs.contains($0.glyph) }) { permission in
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                SettingsRow(glyph: permission.glyph, title: permission.title, value: permission.state)
            }.buttonStyle(SettingsPressStyle())
        }
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
