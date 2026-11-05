// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/theme/{palette,accent,semantic_colors,surfaces,glass,backdrop,typography,shapes,motion,app_theme}.dart.
// Portions derived from PiPilot (https://github.com/CikeSeven/pi_pilot), MIT,
// Copyright (c) 2026 CikeSeven. See THIRD_PARTY_NOTICES.md.
import SwiftUI
import UIKit

// MARK: Colors

extension Color {
    /// 0xAARRGGBB, like Flutter's Color.
    init(argb: UInt32) {
        self.init(.sRGB,
                  red: Double((argb >> 16) & 0xFF) / 255, green: Double((argb >> 8) & 0xFF) / 255,
                  blue: Double(argb & 0xFF) / 255, opacity: Double((argb >> 24) & 0xFF) / 255)
    }
    /// Light / dark pair that follows the trait collection.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(argb: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
    /// Same base colour in both modes with mode-specific opacity.
    init(light: UInt32, lightAlpha: Double, dark: UInt32, darkAlpha: Double) {
        self.init(uiColor: UIColor { traits in
            let dark_ = traits.userInterfaceStyle == .dark
            return UIColor(Color(argb: dark_ ? dark : light).opacity(dark_ ? darkAlpha : lightAlpha))
        })
    }
}

/// Mist Glass palette (default accent "mist"). Views read these roles, never literals.
enum DS {
    // Page
    static let backdropTop = Color(light: 0xFFEBF1FE, dark: 0xFF1D222C)
    static let backdropBottom = Color(light: 0xFFF6F7FC, dark: 0xFF1B1C23)
    static let surface = Color(light: 0xFFF0F4FD, dark: 0xFF1C1F28)
    static let surfaceLow = Color(light: 0xFFF6F9FE, dark: 0xFF232730)
    static let surfaceContainer = Color(light: 0xFFEEF1F9, dark: 0xFF272C36)
    static let surfaceHigh = Color(light: 0xFFE7EBF4, dark: 0xFF2D323C)

    // Text
    static let ink = Color(light: 0xFF1E232E, dark: 0xFFE6E9F0)
    static let inkMuted = Color(light: 0xFF4F5562, dark: 0xFFB6BBC5)
    static let inkFaint = Color(light: 0xFF646974, dark: 0xFF9A9EA9)
    static let inkGhost = Color(light: 0xFFA1A5AC, dark: 0xFF656971)
    static let outline = Color(light: 0xFF7E838D, dark: 0xFF737781)
    static let rule = Color(light: 0xFFDCE0E8, dark: 0xFF343841)

    // Accent (mist)
    static let accentPressed = Color(light: 0xFF3D569D, dark: 0xFF859EDC)
    static var onAccent: Color { Color(light: 0xFFFFFFFF, dark: 0xFF121C34) }
    static let userBubble = Color(light: 0xFFD9E4FD, dark: 0xFF293144)
    static let secondaryContainer = Color(light: 0xFFE2E6F0, dark: 0x17FFFFFF)

    // Semantic
    static let dusk = Color(light: 0xFF6B578F, dark: 0xFFBEAEDE)
    static let duskContainer = Color(light: 0xFFECE5FB, dark: 0xFF3E3451)
    static let danger = Color(light: 0xFFA54743, dark: 0xFFE69089)
    static let dangerContainer = Color(light: 0xFFFFE2E0, dark: 0xFF542C29)
    static let success = Color(light: 0xFF337250, dark: 0xFF8BCCA6)
    static let successContainer = Color(light: 0xFFD9F0E1, dark: 0xFF233F2F)
    static let warn = Color(light: 0xFF936123, dark: 0xFFE6BD7C)
    static let warnContainer = Color(light: 0xFFF9E9CE, dark: 0xFF4C371D)


    static let onDanger = Color(light: 0xFFFDF9F8, dark: 0xFF331513)
    static let onDangerContainer = Color(light: 0xFF642724, dark: 0xFFF8D9D7)
    static let onSuccessContainer = Color(light: 0xFF153F29, dark: 0xFFC9E7D4)
    static let onWarnContainer = Color(light: 0xFF55350D, dark: 0xFFF4E2C3)
    static let info = Color(light: 0xFF2971A7, dark: 0xFF8CBDE8)
    static let infoContainer = Color(light: 0xFFDBECFC, dark: 0xFF253C4F)
    static let onInfoContainer = Color(light: 0xFF123B5A, dark: 0xFFD1E4F4)
    static let identity: [(fill: Color, ink: Color)] = [
        (Color(light: 0xFFDAECFF, dark: 0xFF243A50), Color(light: 0xFF173F65, dark: 0xFFC5DEF8)),
        (Color(light: 0xFFE9E6FF, dark: 0xFF38334F), Color(light: 0xFF3E3463, dark: 0xFFDBD6F7)),
        (Color(light: 0xFFF9E1F3, dark: 0xFF472E42), Color(light: 0xFF562B4E, dark: 0xFFEFD0E7)),
        (Color(light: 0xFFFFE2E0, dark: 0xFF4E2E2D), Color(light: 0xFF602A2A, dark: 0xFFF7D0CD)),
        (Color(light: 0xFFF8E6D1, dark: 0xFF47341A), Color(light: 0xFF563500, dark: 0xFFEED7BB)),
        (Color(light: 0xFFE0EFD8, dark: 0xFF2D3E24), Color(light: 0xFF2A4618, dark: 0xFFCEE2C4)),
        (Color(light: 0xFFD3F1E9, dark: 0xFF174038), Color(light: 0xFF00483D, dark: 0xFFBCE5DB)),
        (Color(light: 0xFFD1F0F8, dark: 0xFF153E47), Color(light: 0xFF004552, dark: 0xFFBAE3ED)),
    ]

    static func identityIndex(_ key: String) -> Int {
        let hash = key.utf16.reduce(UInt32(0x811C9DC5)) { ($0 ^ UInt32($1)) &* 0x01000193 }
        return Int(hash) % identity.count
    }

    static let capsuleTrack = Color(light: 0x0F1E232E, dark: 0x12FFFFFF)
    static let searchFill = Color(light: 0x0D1E232E, dark: 0x12FFFFFF)
    static let segmentThumb = Color(light: 0xFFFFFFFF, dark: 0x33FFFFFF)
    static let switchTrack = Color(light: 0x381E232E, dark: 0x38E6E9F0)
    static let switchKnob = Color(light: 0xFFFFFFFF, dark: 0xFFE6E9F0)

    // Code well
    static let codeWell = Color(light: 0xFFEDF0F6, dark: 0xFF14171E)
    static let codeWellHeader = Color(light: 0xFFE7EBF3, dark: 0xFF1A1E26)
    static let codeWellBorder = Color(light: 0xFFDBDEE5, dark: 0xFF2F333A)
    // Diff roles from DSH Go ui/theme/semantic_colors.dart.
    static let diffAddFill = Color(light: 0xFFDCF4E3, dark: 0xFF1C3424)
    static let diffAddInk = Color(light: 0xFF1F613C, dark: 0xFF98D5AC)
    static let diffDeleteFill = Color(light: 0xFFFFE4E2, dark: 0xFF422423)
    static let diffDeleteInk = Color(light: 0xFF923A37, dark: 0xFFF2A7A1)
    static let lineNumber = Color(light: 0xFF7D8088, dark: 0xFF71747D)
    // Tool tone fills blended with their on-colors, as in trajectory_sheet.dart.
    static let traceTool = Color(light: 0xFF9BA1AE, dark: 0xFF747985)
    static let traceRead = Color(light: 0xFF88A3BE, dark: 0xFF647C95)
    static let traceEdit = Color(light: 0xFFB49C77, dark: 0xFF8A7558)
    static let traceSearch = Color(light: 0xFFA69ABC, dark: 0xFF7D7492)
    static let traceWeb = Color(light: 0xFF7EAB96, dark: 0xFF608270)
    static let traceAgent = Color(light: 0xFFB595AA, dark: 0xFF8C6F82)
    static let traceTodo = Color(light: 0xFF79AAA9, dark: 0xFF548282)
    static let codeComment = Color(light: 0xFF636975, dark: 0xFF868C97)

    /// Shadow base: cool ink in light, near-black in dark.
    static let shadowInk = Color(light: 0xFF0B152D, dark: 0xFF03060D)
    static let scrim = Color(light: 0xFF0B111F, lightAlpha: 0.32, dark: 0xFF000000, darkAlpha: 0.48)
    /// DeepSeek whale tint (whale_tail.dart).
    static let whale = Color(light: 0xFF4D6BFE, dark: 0xFF7A98FB)
}

/// Accent roles remain separate from the fixed identity and status colours.
private struct AccentColors {
    let seed: (UInt32, UInt32)
    let container: (UInt32, UInt32)
    let onContainer: (UInt32, UInt32)
    let onSeedDark: UInt32
    let glow: (UInt32, UInt32)
    let haze: (UInt32, UInt32)
    var hue = 266.0
    var chroma = 1.0

    static func custom(_ argb: UInt32) -> AccentColors {
        let pick = OKLabTone(argb: argb)
        let c = min(0.13, pick.chroma)
        let h = pick.hue
        let k = min(1, c / 0.1255)
        let hue = h * 180 / .pi
        let chroma = 0.8 * k
        func tone(_ l: Double, _ ratio: Double) -> OKLabTone { .init(lightness: l, chroma: c * ratio, hue: h) }
        let l = min(0.6, max(0.3, pick.lightness))
        let onDark = tone(0.231, 0.39).argb
        let light = tone(l, 1).guarded(surface: OKLabTone.retint(0xFFDFE4EE, hue: hue, chroma: chroma),
                                       foreground: 0xFFFFFFFF, dark: false)
        let dark = tone(min(0.93, l + 0.234), 0.76).guarded(
            surface: OKLabTone.retint(0xFF343944, hue: hue, chroma: chroma), foreground: onDark, dark: true)
        return AccentColors(seed: (light, dark),
            container: (tone(0.93, 0.26).argb, tone(0.361, 0.51).argb),
            onContainer: (tone(0.33, 0.70).argb, tone(0.909, 0.24).argb), onSeedDark: onDark,
            glow: (tone(0.819, 0.68).argb, tone(0.52, 0.72).argb),
            haze: (OKLabTone(lightness: 0.86, chroma: 0.045 * k, hue: h + 33 * .pi / 180).argb,
                   OKLabTone(lightness: 0.42, chroma: 0.05 * k, hue: h + 33 * .pi / 180).argb),
            hue: hue, chroma: chroma)
    }

    static let presets: [String: AccentColors] = [
        "mist": AccentColors(seed: (0xFF4B67B4, 0xFF97B1F0),
            container: (0xFFDEE8FF, 0xFF2E3C5F), onContainer: (0xFF213262, 0xFFD8E1F6),
            onSeedDark: 0xFF121C34, glow: (0xFFABC3FC, 0xFF51679D), haze: (0xFFD5CBEB, 0xFF514765)),
        "daiqing": AccentColors(seed: (0xFF236185, 0xFF8CB9D7),
            container: (0xFFDBEAF5, 0xFF274152), onContainer: (0xFF123950, 0xFFD5E3ED),
            onSeedDark: 0xFF0D1F2B, glow: (0xFFA2CAE5, 0xFF466E88), haze: (0xFFC7D0EC, 0xFF444C66), hue: 238, chroma: 0.9),
        "dusk": AccentColors(seed: (0xFF726291, 0xFFB8ABD2),
            container: (0xFFEAE5F4, 0xFF40394F), onContainer: (0xFF392F4C, 0xFFE2DEEC),
            onSeedDark: 0xFF1F1A29, glow: (0xFFC8BDE1, 0xFF6D6284), haze: (0xFFE6C7D7, 0xFF5F4353), hue: 295, chroma: 0.85),
        "turquoise": AccentColors(seed: (0xFF34766F, 0xFF8DBEB7),
            container: (0xFFDBECE9, 0xFF274340), onContainer: (0xFF123D39, 0xFFD6E5E2),
            onSeedDark: 0xFF0D211F, glow: (0xFFA3CEC8, 0xFF47726D), haze: (0xFFB9D7E3, 0xFF34525E), hue: 190, chroma: 0.7),
        "amber": AccentColors(seed: (0xFF8D6636, 0xFFCCAC87),
            container: (0xFFF2E6D9, 0xFF4C3A25), onContainer: (0xFF483011, 0xFFEADFD3),
            onSeedDark: 0xFF271A0C, glow: (0xFFDCBE9D, 0xFF7F6343), haze: (0xFFEAC8C1, 0xFF64443D), hue: 75, chroma: 0.75),
        "graphite": AccentColors(seed: (0xFF2C2E32, 0xFFE5E8ED),
            container: (0xFFE3E6EC, 0xFF3B3D41), onContainer: (0xFF2C2E32, 0xFFDEE1E7),
            onSeedDark: 0xFF191B1E, glow: (0xFFBBBEC3, 0xFF616368), haze: (0xFFCED1D6, 0xFF4A4D52), hue: 262, chroma: 0.25),
        // Stored by earlier iOS builds.
        "teal": AccentColors(seed: (0xFF286C6A, 0xFF84C9C4), container: (0xFFD4EEEA, 0xFF214B49),
            onContainer: (0xFF174A48, 0xFFC2EAE5), onSeedDark: 0xFF0D211F,
            glow: (0xFFA3CEC8, 0xFF47726D), haze: (0xFFB9D7E3, 0xFF34525E)),
        "plum": AccentColors(seed: (0xFF78518B, 0xFFD2ADE5), container: (0xFFF0DFF7, 0xFF4C3359),
            onContainer: (0xFF533265, 0xFFF0D9FA), onSeedDark: 0xFF1F1A29,
            glow: (0xFFC8BDE1, 0xFF6D6284), haze: (0xFFE6C7D7, 0xFF5F4353)),
    ]
}

/// Palette and reading scale flow through SwiftUI's environment, including sheets.
struct DesignTheme {
    var palette = "mist"
    var readingScale: CGFloat = 1
    var glassBlur: Bool
    var fluidMotion: Bool
    private let colors: AccentColors

    init(palette: String = "mist", readingScale: CGFloat = 1, glassBlur: Bool = true,
         customAccent: UInt32? = nil, fluidMotion: Bool = true) {
        self.palette = palette
        self.readingScale = readingScale
        self.glassBlur = glassBlur
        self.fluidMotion = fluidMotion
        colors = customAccent.map(AccentColors.custom) ?? AccentColors.presets[palette] ?? AccentColors.presets["mist"]!
    }

    var backdropTop: Color { neutral(0xFFEBF1FE, 0xFF1D222C) }
    var backdropBottom: Color { neutral(0xFFF6F7FC, 0xFF1B1C23) }
    var ink: Color { neutral(0xFF1E232E, 0xFFE6E9F0) }
    var inkMuted: Color { neutral(0xFF4F5562, 0xFFB6BBC5) }
    var inkFaint: Color { neutral(0xFF646974, 0xFF9A9EA9) }

    private func neutral(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(light: OKLabTone.retint(light, hue: colors.hue, chroma: colors.chroma),
              dark: OKLabTone.retint(dark, hue: colors.hue, chroma: colors.chroma))
    }
    var accent: Color { Color(light: colors.seed.0, dark: colors.seed.1) }
    func contextTone(_ fraction: Double) -> Color {
        if fraction >= 0.85 { return DS.danger }
        return fraction >= 0.6 ? DS.warn : accent
    }
    var onAccent: Color { Color(light: 0xFFFFFFFF, dark: colors.onSeedDark) }
    var accentCheck: Color { Color(argb: colors.seed.0) }
    var accentContainer: Color { Color(light: colors.container.0, dark: colors.container.1) }
    var onAccentContainer: Color { Color(light: colors.onContainer.0, dark: colors.onContainer.1) }
    var glowPrimary: Color {
        Color(light: colors.glow.0, lightAlpha: 0.42, dark: colors.glow.1, darkAlpha: 0.28)
    }
    var glowSecondary: Color {
        Color(light: colors.haze.0, lightAlpha: 0.38, dark: colors.haze.1, darkAlpha: 0.24)
    }
}

private struct DesignThemeKey: EnvironmentKey { static let defaultValue = DesignTheme() }
private struct AppReduceMotionKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var appReduceMotion: Bool {
        get { self[AppReduceMotionKey.self] || accessibilityReduceMotion }
        set { self[AppReduceMotionKey.self] = newValue }
    }
    var designTheme: DesignTheme {
        get { self[DesignThemeKey.self] }
        set { self[DesignThemeKey.self] = newValue }
    }
}

// MARK: Shapes and spacing (shapes.dart)

enum Radius {
    static let xs: CGFloat = 6, sm: CGFloat = 10, md: CGFloat = 14, lg: CGFloat = 20, xl: CGFloat = 28
}

enum Space {
    static let xxs: CGFloat = 2, xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12, lg: CGFloat = 16
    static let xl: CGFloat = 20, xxl: CGFloat = 24, xxxl: CGFloat = 32
    static let gutter: CGFloat = 16, inTurn: CGFloat = 8, betweenTurns: CGFloat = 24
    static let readingWidth: CGFloat = 720, floatInset: CGFloat = 12
}

// Chat run geometry from stream_row.dart, turn_footnote.dart, change_card.dart and diff_page.dart.
enum RunLayout {
    static let processLead: CGFloat = 24
    static let processHeight: CGFloat = 32
    static let processIndent = processLead + Space.sm
    static let actionSize: CGFloat = 36
    static let footnoteSize: CGFloat = 12
    static let fileRowHeight: CGFloat = 40
    static let fileChipHeight: CGFloat = 36
    static let pageBarHeight: CGFloat = 56
    static let diffFontSize: CGFloat = 12
    static let diffNumberSize: CGFloat = 11
    static let diffLineHeight: CGFloat = 19.2
    // DockMetrics / DockStackMetrics in DSH Go ui/chat/dock/.
    static let dockHeight: CGFloat = 36
    static let dockGap: CGFloat = 6
    static let dockGlyph: CGFloat = 20
    static let dockPeek: CGFloat = 6
    static let dockShrink = 0.05
    static let dockSwipe: CGFloat = 48
    static let todoListMax: CGFloat = 196
    static let composerButton: CGFloat = 36
    // Usage sheet and trajectory geometry from DSH Go ui/chat/.
    static let contextRing: CGFloat = 22
    static let panelInset: CGFloat = 20
    static let usageHeadline: CGFloat = 28
    static let usageValue: CGFloat = 20
    static let usageBarHeight: CGFloat = 6
    static let traceBarHeight: CGFloat = 4
    static let stepFactHeight: CGFloat = 36
}

// MARK: Typography (typography.dart): system sans, two weights, mono for code only

enum TextRole {
    case display, pageTitle, headline, hero, setting, title, titleMedium, titleSmall, body, bodyMedium, bodySmall, label, labelMedium, labelSmall, eyebrow

    var size: CGFloat {
        switch self {
        case .display: 28
        case .pageTitle: 26
        case .headline: 22
        case .hero: 20
        case .setting: 15
        case .title: 18
        case .titleMedium, .body: 16
        case .titleSmall, .bodyMedium, .label: 14
        case .bodySmall, .labelMedium, .eyebrow: 12
        case .labelSmall: 11
        }
    }
    var weight: Font.Weight {
        switch self {
        case .display: .light
        case .pageTitle, .headline, .hero, .title, .titleMedium, .titleSmall, .label, .labelMedium, .eyebrow: .semibold
        default: .regular
        }
    }
    /// Line height multiple (Flutter `height`).
    var height: CGFloat {
        switch self {
        case .display: 1.25
        case .pageTitle, .headline: 1.3
        case .hero: 1.35
        case .setting: 1.4
        case .title: 1.4
        case .titleMedium, .titleSmall: 1.45
        case .body: 1.65
        case .bodyMedium: 1.55
        case .bodySmall: 1.5
        case .label: 1.4
        default: 1.35
        }
    }
}

extension View {
    /// Applies a type role using the injected reading preference.
    func type(_ role: TextRole) -> some View { modifier(TypeStyle(role: role)) }
}

private struct TypeStyle: ViewModifier {
    let role: TextRole
    @Environment(\.designTheme) private var theme
    func body(content: Content) -> some View {
        let scale: CGFloat = [.body, .bodyMedium, .bodySmall].contains(role) ? theme.readingScale : 1
        content.font(.system(size: role.size * scale, weight: role.weight))
            .lineSpacing(role.size * scale * (role.height - 1.2))
            .tracking(role == .eyebrow ? 0.8 : role == .labelMedium || role == .labelSmall ? 0.2 : 0)
    }
}

// MARK: Motion (motion.dart)

enum AppMotion {
    static let pressScale: CGFloat = 0.97
    static let press = Animation.spring(duration: 0.15, bounce: 0)
    static let quick = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.16)
    static let standard = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.24)
    static let collapse = Animation.timingCurve(0.645, 0.045, 0.355, 1, duration: 0.28)
    static let glide = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.34)
    static let thumb = Animation.spring(duration: 0.32, bounce: 0.15)
    static let breath = Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)
}

enum Mono {
    /// JetBrains Mono with programming ligatures off (`=>` stays two glyphs), like
    /// AppType.monoFeatures in Flutter. Shaping only; copied text is unchanged.
    static func font(_ size: CGFloat = 13, weight: Font.Weight = .regular, scale: CGFloat = 1) -> Font {
        let size = size * scale
        let name = weight == .bold ? "JetBrainsMono-Bold" : weight == .medium ? "JetBrainsMono-Medium" : "JetBrainsMono-Regular"
        guard let base = UIFont(name: name, size: size) else { return .system(size: size, design: .monospaced) }
        let features: [[UIFontDescriptor.FeatureKey: Int]] = [
            [.type: kLigaturesType, .selector: kCommonLigaturesOffSelector],
            [.type: kContextualAlternatesType, .selector: kContextualAlternatesOffSelector],
        ]
        let descriptor = base.fontDescriptor.addingAttributes([.featureSettings: features])
        return Font(UIFont(descriptor: descriptor, size: size))
    }
}

// MARK: Icons

/// A DshIcons (Phosphor) glyph.
struct Glyph: View {
    let glyph: DshGlyph
    var size: CGFloat = 22
    var body: some View {
        Text(String(UnicodeScalar(glyph.rawValue).map(Character.init) ?? " "))
            .font(.custom("DshIcons", fixedSize: size))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: Backdrop (backdrop.dart): vertical mist gradient + two radial glows

struct AppBackdrop: View {
    @Environment(\.designTheme) private var theme
    var glow = true
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let longest = max(size.width, size.height)
            ZStack {
                LinearGradient(colors: [theme.backdropTop, theme.backdropBottom], startPoint: .top, endPoint: .bottom)
                if glow {
                    RadialGradient(colors: [theme.glowPrimary, theme.glowPrimary.opacity(0)], center: .init(x: 0.92, y: 0),
                                   startRadius: 0, endRadius: longest * 0.62)
                    RadialGradient(colors: [theme.glowSecondary, theme.glowSecondary.opacity(0)], center: .init(x: 0, y: 1),
                                   startRadius: 0, endRadius: longest * 0.55)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: Glass (glass.dart + surfaces.dart)

enum GlassTier { case chrome, sheet, card, pill }

private struct GlassStyle {
    let fill: Color
    let hairline: Color
    let rim: Color
    let blur: Bool
    let shadow: Bool

    static func of(_ tier: GlassTier) -> GlassStyle {
        switch tier {
        case .chrome:
            GlassStyle(fill: Color(light: 0xFFFFFFFF, lightAlpha: 0.70, dark: 0xFF292E39, darkAlpha: 0.72),
                       hairline: Color(light: 0xFF0B152D, lightAlpha: 0.08, dark: 0xFFFFFFFF, darkAlpha: 0.09),
                       rim: Color(light: 0xFFFFFFFF, lightAlpha: 0.85, dark: 0xFFFFFFFF, darkAlpha: 0.12), blur: true, shadow: true)
        case .sheet:
            GlassStyle(fill: Color(light: 0xFFF6F9FE, lightAlpha: 0.82, dark: 0xFF232832, darkAlpha: 0.86),
                       hairline: Color(light: 0xFF0B152D, lightAlpha: 0.07, dark: 0xFFFFFFFF, darkAlpha: 0.08),
                       rim: Color(light: 0xFFFFFFFF, lightAlpha: 0.90, dark: 0xFFFFFFFF, darkAlpha: 0.10), blur: true, shadow: true)
        case .card:
            GlassStyle(fill: Color(light: 0xFFFFFFFF, lightAlpha: 0.62, dark: 0xFFFFFFFF, darkAlpha: 0.05),
                       hairline: Color(light: 0xFF0B152D, lightAlpha: 0.06, dark: 0xFFFFFFFF, darkAlpha: 0.07),
                       rim: Color(light: 0xFFFFFFFF, lightAlpha: 0.70, dark: 0xFFFFFFFF, darkAlpha: 0.06), blur: false, shadow: false)
        case .pill:
            GlassStyle(fill: Color(light: 0xFFFFFFFF, lightAlpha: 0.55, dark: 0xFFFFFFFF, darkAlpha: 0.06),
                       hairline: Color(light: 0xFF0B152D, lightAlpha: 0.07, dark: 0xFFFFFFFF, darkAlpha: 0.08),
                       rim: Color(light: 0xFFFFFFFF, lightAlpha: 0.75, dark: 0xFFFFFFFF, darkAlpha: 0.08), blur: false, shadow: false)
        }
    }
}

/// Blur behind → translucent fill → hairline + top rim highlight → outer shadow.
struct GlassBackground<S: InsettableShape>: ViewModifier {
    let tier: GlassTier
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.designTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let style = GlassStyle.of(tier)
        content
            .background {
                ZStack {
                    if style.blur && !reduceTransparency && theme.glassBlur { shape.fill(.ultraThinMaterial) }
                    shape.fill(style.fill)
                }
                .shadow(color: style.shadow ? DS.shadowInk.opacity(scheme == .dark ? 0.35 : 0.08) : .clear, radius: 12, y: 8)
                .shadow(color: style.shadow ? DS.shadowInk.opacity(scheme == .dark ? 0.25 : 0.05) : .clear, radius: 1.5, y: 1)
            }
            .overlay {
                shape.strokeBorder(style.hairline, lineWidth: 0.5)
                // Top rim highlight: brightest at the top edge, gone by mid-height.
                shape.strokeBorder(LinearGradient(colors: [style.rim, style.rim.opacity(0)], startPoint: .top, endPoint: .center),
                                   lineWidth: 1)
            }
    }
}

extension View {
    func glass(_ tier: GlassTier = .card, radius: CGFloat? = nil) -> some View {
        let r = radius ?? (tier == .chrome || tier == .sheet ? Radius.xl : tier == .card ? Radius.md : Radius.lg)
        return modifier(GlassBackground(tier: tier, shape: RoundedRectangle(cornerRadius: r, style: .continuous)))
    }
    func glassCapsule(_ tier: GlassTier = .chrome) -> some View { modifier(GlassBackground(tier: tier, shape: Capsule())) }
    func glassCircle(_ tier: GlassTier = .chrome) -> some View { modifier(GlassBackground(tier: tier, shape: Circle())) }
}

/// Round chrome button (header menu / new chat): 36pt circle, 22pt glyph.
struct GlassIconButton: View {
    let glyph: DshGlyph
    let label: LocalizedStringKey
    var size: CGFloat = 40
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Glyph(glyph: glyph, size: 22)
                .foregroundStyle(DS.ink)
                .frame(width: size, height: size)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}
