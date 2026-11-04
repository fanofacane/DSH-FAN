// SPDX-License-Identifier: AGPL-3.0-or-later
// Mist Glass design system, ported from 原 Flutter 版 lib/ui/theme (palette.dart, accent.dart,
// surfaces.dart, glass.dart, backdrop.dart, typography.dart, shapes.dart).
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
    static let glowPrimary = Color(light: 0xFFABC3FC, lightAlpha: 0.42, dark: 0xFF51679D, darkAlpha: 0.28)
    static let glowSecondary = Color(light: 0xFFD5CBEB, lightAlpha: 0.38, dark: 0xFF514765, darkAlpha: 0.24)
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

    // Code well
    static let codeWell = Color(light: 0xFFEDF0F6, dark: 0xFF14171E)
    static let codeWellHeader = Color(light: 0xFFE7EBF3, dark: 0xFF1A1E26)
    static let codeWellBorder = Color(light: 0xFFDBDEE5, dark: 0xFF2F333A)
    static let codeComment = Color(light: 0xFF636975, dark: 0xFF868C97)

    /// Shadow base: cool ink in light, near-black in dark.
    static let shadowInk = Color(light: 0xFF0B152D, dark: 0xFF03060D)
    static let scrim = Color(light: 0xFF0B111F, lightAlpha: 0.32, dark: 0xFF000000, darkAlpha: 0.48)
    /// DeepSeek whale tint (whale_tail.dart).
    static let whale = Color(light: 0xFF4D6BFE, dark: 0xFF7A98FB)
}

/// Palette and reading scale flow through SwiftUI's environment, including sheets.
struct DesignTheme {
    var palette = "mist"
    var readingScale: CGFloat = 1
    var accent: Color {
        switch palette {
        case "teal": Color(light: 0xFF286C6A, dark: 0xFF84C9C4)
        case "plum": Color(light: 0xFF78518B, dark: 0xFFD2ADE5)
        default: Color(light: 0xFF4B67B4, dark: 0xFF97B1F0)
        }
    }
    var accentContainer: Color {
        switch palette {
        case "teal": Color(light: 0xFFD4EEEA, dark: 0xFF214B49)
        case "plum": Color(light: 0xFFF0DFF7, dark: 0xFF4C3359)
        default: Color(light: 0xFFDEE8FF, dark: 0xFF2E3C5F)
        }
    }
    var onAccentContainer: Color {
        switch palette {
        case "teal": Color(light: 0xFF174A48, dark: 0xFFC2EAE5)
        case "plum": Color(light: 0xFF533265, dark: 0xFFF0D9FA)
        default: Color(light: 0xFF213262, dark: 0xFFD8E1F6)
        }
    }
}

private struct DesignThemeKey: EnvironmentKey { static let defaultValue = DesignTheme() }
extension EnvironmentValues {
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

// MARK: Typography (typography.dart): system sans, two weights, mono for code only

enum TextRole {
    case display, headline, title, titleMedium, titleSmall, body, bodyMedium, bodySmall, label, labelMedium, labelSmall, eyebrow

    var size: CGFloat {
        switch self {
        case .display: 28
        case .headline: 22
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
        case .headline, .title, .titleMedium, .titleSmall, .label, .labelMedium, .eyebrow: .semibold
        default: .regular
        }
    }
    /// Line height multiple (Flutter `height`).
    var height: CGFloat {
        switch self {
        case .display: 1.25
        case .headline: 1.3
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
    var glow = true
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let longest = max(size.width, size.height)
            ZStack {
                LinearGradient(colors: [DS.backdropTop, DS.backdropBottom], startPoint: .top, endPoint: .bottom)
                if glow {
                    RadialGradient(colors: [DS.glowPrimary, DS.glowPrimary.opacity(0)], center: .init(x: 0.92, y: 0),
                                   startRadius: 0, endRadius: longest * 0.62)
                    RadialGradient(colors: [DS.glowSecondary, DS.glowSecondary.opacity(0)], center: .init(x: 0, y: 1),
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
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let style = GlassStyle.of(tier)
        content
            .background {
                ZStack {
                    if style.blur && !reduceTransparency { shape.fill(.ultraThinMaterial) }
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
