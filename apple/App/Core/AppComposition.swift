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
    let preferences: AppPreferences
    let runtime: any EngineControlling
    let intents: IntentInbox
    let engine: EngineModel
    private(set) lazy var chat = AppSession(hosts: hosts, phone: phone, notifications: notifications, intents: intents)
    let phone: PhoneController
    let pet: PetModel
    private(set) lazy var hosts = HostStore(runtime: runtime, relay: relay, events: self)
    let relay: RelayStore
    let notifications: TaskNotifications
    let activity = TurnActivityController()
    let appearanceImages = AppearanceImages()
    let icons: AlternateIconController
    let audioSession: AVAudioSession
    let photoLibrary: PHPhotoLibrary

    init() {
        #if DEBUG
        if DebugPageRegistry.usesFixture, let defaults = UserDefaults(suiteName: "DSHGoldenFixture") {
            defaults.removePersistentDomain(forName: "DSHGoldenFixture")
            preferences = AppPreferences(defaults: defaults)
            pet = PetModel(defaults: defaults)
            if let pack = DebugPageRegistry.argument("-dsh-screen-pet") { pet.select(pack) }
            if let size = DebugPageRegistry.argument("-dsh-screen-pet-size").flatMap(PetSize.init(rawValue:)) {
                pet.preferences.size = size
            }
            if DebugPageRegistry.argument("-dsh-screen-fixture") == "overlay" {
                pet.preferences.outside = true
                pet.outsideSnoozedUntil = .now.addingTimeInterval(3600)
            }
        } else {
            preferences = AppPreferences()
            pet = PetModel()
        }
        #else
        preferences = AppPreferences()
        pet = PetModel()
        #endif
        // iSH owns one process-wide kernel; only composition selects its concrete runtime.
        let runtime = RuntimeEngine.shared
        // App Intents are created by the OS; their callback inbox must be the same instance.
        intents = IntentInbox.shared
        // UIKit, audio, photos and AlarmKit provide process-wide system services.
        let application = UIApplication.shared
        icons = AlternateIconController(application: application)
        #if DEBUG
        if DebugPageRegistry.usesFixture, DebugPageRegistry.argument("-dsh-screen-fixture") == "custom" {
            appearanceImages.seedPreview()
            preferences.wallpaperOn = true
            preferences.launchImageOn = true
            preferences.launchFill = DebugPageRegistry.argument("-dsh-screen-fit") != "center"
        }
        #endif
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
    @Environment(AppearanceImages.self) private var images
    @State private var lightweight = PerformanceMode.auto.isLightweight
    private var usesFixture: Bool {
        #if DEBUG
        DebugPageRegistry.usesFixture
        #else
        false
        #endif
    }

    func body(content: Content) -> some View {
        let lightweight = preferences.performanceMode == .auto ? self.lightweight : preferences.performanceMode == .light
        let blur = preferences.useModeEffects ? !lightweight : preferences.glassBlur
        let motion = preferences.useModeEffects ? lightweight : preferences.reduceMotion
        let custom = preferences.palette == "wallpaper" ? images.wallpaperAccent : preferences.palette == "custom" ? preferences.customAccent : nil
        let theme = DesignTheme(palette: preferences.palette, readingScale: preferences.scale, glassBlur: blur,
                                customAccent: custom, fluidMotion: preferences.fluidMotion && !lightweight)
        content.preferredColorScheme(usesFixture ? nil : preferences.colorScheme)
            .environment(\.designTheme, theme)
            .environment(\.appReduceMotion, usesFixture || motion)
            .tint(theme.accent)
            .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
                self.lightweight = PerformanceMode.auto.isLightweight
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                self.lightweight = PerformanceMode.auto.isLightweight
            }
    }
}
