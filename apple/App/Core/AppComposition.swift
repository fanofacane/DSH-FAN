// SPDX-License-Identifier: AGPL-3.0-or-later
import AlarmKit
import AVFoundation
import DSHRuntime
import Photos
import SwiftUI
import UIKit
import UserNotifications

/// The app's composition root. Features receive these instances or narrow protocols.
@MainActor final class AppComposition: HostLinkEvents {
    let preferences = AppPreferences()
    let runtime: any EngineControlling
    let intents: IntentInbox
    let engine: EngineModel
    private(set) lazy var chat = AppSession(hosts: hosts, phone: phone, notifications: notifications, intents: intents)
    let phone: PhoneController
    let pet = PetModel()
    private(set) lazy var hosts = HostStore(runtime: runtime, relay: relay, events: self)
    let relay: RelayStore
    let notifications: TaskNotifications
    let activity = TurnActivityController()
    let audioSession: AVAudioSession
    let photoLibrary: PHPhotoLibrary

    init() {
        // iSH owns one process-wide kernel; only composition selects its concrete runtime.
        let runtime = RuntimeEngine.shared
        // App Intents are created by the OS; their callback inbox must be the same instance.
        intents = IntentInbox.shared
        // UIKit, audio, photos and AlarmKit provide process-wide system services.
        let application = UIApplication.shared
        audioSession = AVAudioSession.sharedInstance()
        photoLibrary = PHPhotoLibrary.shared()
        let alarms: PhoneAlarms
        if #available(iOS 26, *) { alarms = PhoneAlarms(AlarmManager.shared) }
        else { alarms = .unavailable }
        self.runtime = runtime
        relay = RelayStore(application: application)
        phone = PhoneController(runtime: runtime, executor: PhoneExecutor(application: application, alarms: alarms))
        runtime.launchHook = AppRuntimeHook.make(phone: phone.runtimeLaunchHook, plugins: PluginCatalog.bundled, gate: LocalPluginGate())
        notifications = TaskNotifications(center: .current(), application: application)
        engine = EngineModel(runtime: runtime, phone: phone)
        _ = chat
    }
    func hostLinkLost() { chat.connection.linkLost() }
}

private struct AudioSessionKey: EnvironmentKey { static let defaultValue: AVAudioSession? = nil }
private struct PhotoLibraryKey: EnvironmentKey { static let defaultValue: PHPhotoLibrary? = nil }

extension EnvironmentValues {
    // SwiftUI reads key defaults before applying ancestor values; defaults stay inert.
    var audioSession: AVAudioSession? {
        get { self[AudioSessionKey.self] }
        set { self[AudioSessionKey.self] = newValue }
    }
    var photoLibrary: PHPhotoLibrary? {
        get { self[PhotoLibraryKey.self] }
        set { self[PhotoLibraryKey.self] = newValue }
    }
}

/// Observe appearance inside a view so changes update descendants and presented sheets.
struct AppAppearance: ViewModifier {
    @Environment(AppPreferences.self) private var preferences
    private var usesFixture: Bool {
        #if DEBUG
        DebugPageRegistry.usesFixture
        #else
        false
        #endif
    }

    func body(content: Content) -> some View {
        let theme = usesFixture ? DesignTheme() : DesignTheme(palette: preferences.palette, readingScale: preferences.scale)
        content.preferredColorScheme(usesFixture ? nil : preferences.colorScheme)
            .environment(\.designTheme, theme)
            .tint(theme.accent)
    }
}
