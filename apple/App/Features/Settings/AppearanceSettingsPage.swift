// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/settings/appearance/{appearance_page,tile_style_picker,app_icon_picker}.dart
// and ui/theme/theme_reveal.dart.
import SwiftUI
import UIKit

struct AppearanceSettingsPage: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(AppearanceImages.self) private var images
    @Environment(\.designTheme) private var theme
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var reveal = ThemeReveal()

    private let presets: [(String, LocalizedStringKey)] = [
        ("mist", "Mist blue"), ("daiqing", "Ink blue"), ("dusk", "Dusk"),
        ("turquoise", "Turquoise"), ("amber", "Amber"), ("graphite", "Graphite"),
    ]

    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage(title: "Theme") {
            SettingsGroup(header: "Color mode") {
                HStack(alignment: .top, spacing: Space.md) {
                    mode("light", "Light")
                    mode("dark", "Dark")
                    mode("system", "Follow system")
                }
                .padding(Space.lg)
            }.settingAnchor("theme-mode")
            SettingsGroup(header: "Accent color") {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(presets, id: \.0) { id, label in
                        swatch(label, id: id, color: DesignTheme(palette: id).accent)
                    }
                    swatch("Custom", id: "custom", color: Color(argb: preferences.customAccent), multicolor: true)
                }
                .padding(.horizontal, Space.sm).padding(.vertical, Space.lg)
                ExpandReveal(open: preferences.palette == "custom") {
                    ColorPicker("Custom color", selection: Binding(
                        get: { Color(argb: preferences.customAccent) },
                        set: { color in
                            if let argb = color.opaqueARGB { preferences.customAccent = argb }
                        }
                    ), supportsOpacity: false)
                    .settingsType(.setting).padding(.horizontal, Space.lg).frame(minHeight: SettingsMetrics.row)
                }
                if let accent = images.wallpaperAccent {
                    SettingsToggleRow(title: "Follow wallpaper", isOn: Binding(
                        get: { preferences.palette == "wallpaper" },
                        set: { on in change { preferences.palette = on ? "wallpaper" : "mist" } }
                    ))
                    .tint(Color(argb: accent))
                }
            }.settingAnchor("accent")

            SettingsGroup(header: "Feature icons") {
                HStack(spacing: Space.md) {
                    tileStyle("tinted", "Flat two-tone")
                    tileStyle("line", "Minimal geometry")
                    tileStyle("glass", "Glass gradient")
                }.padding(Space.lg)
            }.settingAnchor("tile-style")

            SettingsGroup(header: "App icon") { AlternateIconPicker() }
                .settingAnchor("app-icon")
            SettingsGroup(header: "Launch screen", footer: "The image plays when DSH Fan opens, after the iOS launch screen.") {
                AppearanceImageSection(kind: .launch)
            }.settingAnchor("launch-screen")
            SettingsGroup(header: "Wallpaper", footer: "Shown behind the conversation and its drawer.") {
                AppearanceImageSection(kind: .wallpaper)
            }.settingAnchor("wallpaper")
        }
        .background { ThemeRevealMarker(reveal: reveal) }
        .onAppear {
            #if DEBUG
            if DebugPageRegistry.usesFixture, DebugPageRegistry.argument("-dsh-screen-fixture") == "custom" {
                preferences.palette = "custom"
                preferences.customAccent = 0xFFB46836
            }
            #endif
        }
    }

    private func mode(_ id: String, _ label: LocalizedStringKey) -> some View {
        Button { change { preferences.appearance = id } } label: {
            AppearanceChoice(label: label, selected: preferences.appearance == id, aspect: 0.78) {
                ZStack {
                    if id == "system" {
                        HStack(spacing: 0) { Color(argb: 0xFFEBF1FE); Color(argb: 0xFF1D222C) }
                    } else {
                        Color(argb: id == "light" ? 0xFFEBF1FE : 0xFF1D222C)
                    }
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Capsule().fill(theme.accentContainer).frame(height: 12)
                        Capsule().fill(theme.accent.opacity(0.4)).frame(width: 28, height: 5)
                        Spacer()
                        Capsule().fill(theme.accentContainer).frame(height: 16)
                    }.padding(Space.sm)
                }
            }
        }
        .buttonStyle(SettingsPressStyle(scales: true))
    }

    private func swatch(_ label: LocalizedStringKey, id: String, color: Color, multicolor: Bool = false) -> some View {
        Button { change { preferences.palette = id } } label: {
            let selected = preferences.palette == id
            VStack(spacing: Space.sm) {
                Circle().fill(color).frame(width: 30, height: 30)
                    .overlay {
                        if multicolor {
                            Circle().strokeBorder(AngularGradient(colors: [.purple, .blue, .green, .orange, .purple], center: .center),
                                                  lineWidth: 5)
                        }
                    }
                    .padding(4)
                    .overlay { Circle().strokeBorder(selected ? theme.accent : .clear, lineWidth: 2) }
                Text(label).settingsType(.labelMedium).foregroundStyle(selected ? theme.accent : theme.inkMuted)
                    .lineLimit(1).minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }.buttonStyle(SettingsPressStyle(scales: true))
    }

    private func tileStyle(_ style: String, _ label: LocalizedStringKey) -> some View {
        Button { preferences.featureIconStyle = style } label: {
            AppearanceChoice(label: label, selected: preferences.featureIconStyle == style, aspect: 1) {
                let glyphs: [DshGlyph] = [AppIcon.terminal, AppIcon.history, AppIcon.providers, AppIcon.phoneControl]
                LazyVGrid(columns: [GridItem(.fixed(28)), GridItem(.fixed(28))], spacing: Space.xs) {
                    ForEach(Array(glyphs.enumerated()), id: \.offset) { index, glyph in
                        if style == "line" {
                            Glyph(glyph: glyph, size: 20).foregroundStyle(theme.accent)
                        } else if style == "glass" {
                            Glyph(glyph: glyph, size: 18).foregroundStyle(theme.onAccent)
                                .frame(width: 26, height: 26)
                                .background(LinearGradient(colors: [theme.accent, theme.accent.opacity(0.4)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                                            in: RoundedRectangle(cornerRadius: Radius.xs))
                        } else {
                            SettingsIcon(glyph: glyph, tone: .identity(index), size: 26)
                        }
                    }
                }
            }
        }.buttonStyle(SettingsPressStyle(scales: true))
    }

    private func change(_ action: () -> Void) {
        if reduceMotion { action() } else { reveal.change(action) }
    }
}

struct AppearanceChoice<Preview: View>: View {
    let label: LocalizedStringKey
    let selected: Bool
    let aspect: CGFloat
    @ViewBuilder let preview: () -> Preview
    @Environment(\.designTheme) private var theme

    var body: some View {
        VStack(spacing: Space.sm) {
            Color.clear.aspectRatio(aspect, contentMode: .fit)
                .overlay { preview() }
                .background(DS.searchFill)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(selected ? theme.accent : DS.rule, lineWidth: selected ? 2 : 1)
                }
            Text(label).settingsType(.labelMedium).lineLimit(1)
                .foregroundStyle(selected ? theme.accent : DS.inkMuted)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// UIKit snapshots preserve the old native chrome until the new SwiftUI
/// color scheme renders. The even-odd mask opens from the selected card area.
@MainActor final class ThemeReveal {
    weak var marker: UIView?
    private weak var overlay: UIView?

    func change(_ action: () -> Void) {
        overlay?.removeFromSuperview()
        guard let marker, let window = marker.window, let snapshot = window.snapshotView(afterScreenUpdates: false) else {
            action()
            return
        }
        snapshot.frame = window.bounds
        snapshot.isUserInteractionEnabled = false
        snapshot.accessibilityElementsHidden = true
        window.addSubview(snapshot)
        overlay = snapshot
        let center = CGPoint(x: window.bounds.midX, y: window.bounds.height * 0.3)
        let radius = hypot(window.bounds.width / 2, window.bounds.height * 0.7)
        let mask = CAShapeLayer()
        mask.fillRule = .evenOdd
        func path(_ radius: CGFloat) -> CGPath {
            let path = CGMutablePath()
            path.addRect(snapshot.bounds)
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            return path
        }
        snapshot.layer.mask = mask
        mask.path = path(1)
        action()
        CATransaction.begin()
        CATransaction.setCompletionBlock { snapshot.removeFromSuperview() }
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = mask.path
        animation.toValue = path(radius)
        animation.duration = 0.48
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        mask.path = path(radius)
        mask.add(animation, forKey: "themeReveal")
        CATransaction.commit()
    }
}

struct ThemeRevealMarker: UIViewRepresentable {
    let reveal: ThemeReveal
    func makeUIView(context: Context) -> UIView {
        let marker = UIView()
        marker.isUserInteractionEnabled = false
        reveal.marker = marker
        return marker
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

@MainActor @Observable final class AlternateIconController {
    private let application: UIApplication
    let names: [String]
    private(set) var selected: String?

    init(application: UIApplication, bundle: Bundle = .main) {
        self.application = application
        let phone = bundle.infoDictionary?["CFBundleIcons"] as? [String: Any]
        let tablet = bundle.infoDictionary?["CFBundleIcons~ipad"] as? [String: Any]
        let icons = (UIDevice.current.userInterfaceIdiom == .pad ? tablet : nil) ?? phone
        names = (icons?["CFBundleAlternateIcons"] as? [String: Any])?.keys.sorted() ?? []
        selected = application.alternateIconName
    }

    var supported: Bool { application.supportsAlternateIcons }

    func choose(_ name: String?) async throws {
        try await application.setAlternateIconName(name)
        selected = application.alternateIconName
    }
}

struct AlternateIconPicker: View {
    @Environment(AlternateIconController.self) private var icons
    @State private var changing = false
    @State private var error: String?

    var body: some View {
        HStack(spacing: Space.md) {
            choice(nil)
            ForEach(icons.names, id: \.self) { name in choice(name) }
        }.padding(Space.lg)
        if let error { Text("Request failed: \(error)").settingsType(.bodySmall).foregroundStyle(DS.danger).padding(.bottom, Space.sm) }
    }

    private func choice(_ name: String?) -> some View {
        Button {
            changing = true
            Task {
                defer { changing = false }
                do { try await icons.choose(name); error = nil }
                catch { self.error = "E_ALTERNATE_ICON" }
            }
        } label: {
            AppearanceChoice(label: name.map { LocalizedStringKey($0) } ?? "Default", selected: icons.selected == name, aspect: 1) {
                if let name, let image = UIImage(named: name) {
                    Image(uiImage: image).resizable().scaledToFit().padding(Space.sm)
                } else {
                    BrandMark(size: 44)
                }
            }.frame(maxWidth: 102)
        }
        .buttonStyle(SettingsPressStyle(scales: true))
        .disabled(changing || !icons.supported || icons.selected == name)
    }
}
