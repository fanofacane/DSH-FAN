// SPDX-License-Identifier: AGPL-3.0-or-later
import Observation
import SwiftUI

// DSH Go: app/lib/state/settings_state.dart and ui/settings/search/settings_search_page.dart.
@Observable final class AppPreferences {
    private let defaults: UserDefaults
    var appearance: String { didSet { defaults.set(appearance, forKey: "ui.appearance") } }
    var palette: String { didSet { defaults.set(palette, forKey: "ui.palette") } }
    var textScale: Double { didSet { defaults.set(textScale, forKey: "ui.textScale") } }
    var remoteImages: Bool { didSet { defaults.set(remoteImages, forKey: "privacy.remoteImages") } }
    var foldCompletedTurns: Bool { didSet { defaults.set(foldCompletedTurns, forKey: "ui.foldCompletedTurns") } }
    var reduceMotion: Bool { didSet { defaults.set(reduceMotion, forKey: "ui.reduceMotion") } }
    var glassBlur: Bool { didSet { defaults.set(glassBlur, forKey: "ui.glassBlur") } }
    var voiceInputEnabled: Bool { didSet { defaults.set(voiceInputEnabled, forKey: "ui.voiceInput") } }
    var quickPanelEnabled: Bool { didSet { defaults.set(quickPanelEnabled, forKey: "ui.quickPanel") } }
    var quickPanelItems: [QuickPanelItem] { didSet { defaults.set(quickPanelItems.map(\.rawValue), forKey: "ui.quickPanel.items") } }
    var customAccent: UInt32 { didSet { defaults.set(customAccent, forKey: "ui.customAccent") } }
    var featureIconStyle: String { didSet { defaults.set(featureIconStyle, forKey: "ui.featureIconStyle") } }
    var wallpaperOn: Bool { didSet { defaults.set(wallpaperOn, forKey: "ui.wallpaperOn") } }
    var launchImageOn: Bool { didSet { defaults.set(launchImageOn, forKey: "ui.launchImageOn") } }
    var launchFill: Bool { didSet { defaults.set(launchFill, forKey: "ui.launchFill") } }
    var launchBackground: String { didSet { defaults.set(launchBackground, forKey: "ui.launchBackground") } }
    var wallpaperBlur: Double { didSet { defaults.set(wallpaperBlur, forKey: "ui.wallpaperBlur") } }
    var wallpaperLighten: Double { didSet { defaults.set(wallpaperLighten, forKey: "ui.wallpaperLighten") } }
    var wallpaperDim: Double { didSet { defaults.set(wallpaperDim, forKey: "ui.wallpaperDim") } }
    var voiceLocale: String { didSet { defaults.set(voiceLocale, forKey: "ui.voiceLocale") } }
    var voiceOfflineOnly: Bool { didSet { defaults.set(voiceOfflineOnly, forKey: "ui.voiceOfflineOnly") } }
    var showLiveActivity: Bool { didSet { defaults.set(showLiveActivity, forKey: "ui.liveActivity") } }
    var visualReplies: Bool { didSet { defaults.set(visualReplies, forKey: "ui.visualReplies") } }
    var fluidMotion: Bool { didSet { defaults.set(fluidMotion, forKey: "ui.fluidMotion") } }
    var performanceMode: PerformanceMode { didSet { defaults.set(performanceMode.rawValue, forKey: "ui.performanceMode") } }
    var useModeEffects: Bool { didSet { defaults.set(useModeEffects, forKey: "ui.useModeEffects") } }
    var wallpaperFrame: WallpaperFrame {
        didSet {
            defaults.set(wallpaperFrame.zoom, forKey: "ui.wallpaperZoom")
            defaults.set(wallpaperFrame.x, forKey: "ui.wallpaperX")
            defaults.set(wallpaperFrame.y, forKey: "ui.wallpaperY")
        }
    }
    var language: String {
        didSet {
            defaults.set(language, forKey: "ui.language")
            if language == "system" { defaults.removeObject(forKey: "AppleLanguages") }
            else { defaults.set([language], forKey: "AppleLanguages") }
        }
    }
    private(set) var recentSettingsSearches: [String] {
        didSet { defaults.set(recentSettingsSearches, forKey: "settings_search.recent") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: "ui.appearance") ?? "system"
        palette = defaults.string(forKey: "ui.palette") ?? "mist"
        textScale = defaults.object(forKey: "ui.textScale") as? Double ?? 1
        remoteImages = defaults.object(forKey: "privacy.remoteImages") as? Bool ?? true
        foldCompletedTurns = defaults.object(forKey: "ui.foldCompletedTurns") as? Bool ?? true
        reduceMotion = defaults.bool(forKey: "ui.reduceMotion")
        glassBlur = defaults.object(forKey: "ui.glassBlur") as? Bool ?? true
        voiceInputEnabled = defaults.object(forKey: "ui.voiceInput") as? Bool ?? true
        quickPanelEnabled = defaults.bool(forKey: "ui.quickPanel")
        let savedItems = defaults.stringArray(forKey: "ui.quickPanel.items")?.compactMap(QuickPanelItem.init(rawValue:))
        var seen: Set<QuickPanelItem> = []
        quickPanelItems = (savedItems ?? QuickPanelItem.allCases).filter { seen.insert($0).inserted }
        customAccent = defaults.object(forKey: "ui.customAccent") == nil ? 0xFF4B67B4 : UInt32(clamping: defaults.integer(forKey: "ui.customAccent"))
        featureIconStyle = defaults.string(forKey: "ui.featureIconStyle") ?? "tinted"
        wallpaperOn = defaults.bool(forKey: "ui.wallpaperOn")
        launchImageOn = defaults.bool(forKey: "ui.launchImageOn")
        launchFill = defaults.object(forKey: "ui.launchFill") as? Bool ?? true
        launchBackground = defaults.string(forKey: "ui.launchBackground") ?? "theme"
        wallpaperBlur = defaults.object(forKey: "ui.wallpaperBlur") as? Double ?? 0.3
        wallpaperLighten = defaults.object(forKey: "ui.wallpaperLighten") as? Double ?? 0.2
        wallpaperDim = defaults.object(forKey: "ui.wallpaperDim") as? Double ?? 0.2
        voiceLocale = defaults.string(forKey: "ui.voiceLocale") ?? "system"
        voiceOfflineOnly = defaults.bool(forKey: "ui.voiceOfflineOnly")
        showLiveActivity = defaults.object(forKey: "ui.liveActivity") as? Bool ?? true
        visualReplies = defaults.object(forKey: "ui.visualReplies") as? Bool ?? true
        fluidMotion = defaults.object(forKey: "ui.fluidMotion") as? Bool ?? true
        performanceMode = defaults.string(forKey: "ui.performanceMode").flatMap(PerformanceMode.init(rawValue:)) ?? .auto
        useModeEffects = defaults.object(forKey: "ui.useModeEffects") as? Bool ?? (defaults.object(forKey: "ui.glassBlur") == nil && defaults.object(forKey: "ui.reduceMotion") == nil)
        wallpaperFrame = WallpaperFrame(zoom: defaults.object(forKey: "ui.wallpaperZoom") as? Double ?? 1,
                                        x: defaults.double(forKey: "ui.wallpaperX"), y: defaults.double(forKey: "ui.wallpaperY"))
        language = defaults.string(forKey: "ui.language") ?? "system"
        recentSettingsSearches = Array((defaults.stringArray(forKey: "settings_search.recent") ?? []).prefix(5))
    }

    func rememberSettingsSearch(_ query: String) {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        recentSettingsSearches = Array(([term] + recentSettingsSearches.filter { $0 != term }).prefix(5))
    }

    var colorScheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
    var scale: CGFloat { CGFloat(min(1.3, max(0.9, textScale.isFinite ? textScale : 1))) }
    var textScaleChoice: Double {
        [0.9, 1, 1.15, 1.3].min { abs($0 - Double(scale)) < abs($1 - Double(scale)) } ?? 1
    }
}
