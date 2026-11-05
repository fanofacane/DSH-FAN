// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/settings/settings_widgets.dart, ui/shell/page_frame.dart,
// ui/common/{app_sheet,overview_card,list_page_row,pressable}.dart and ui/theme/app_theme.dart.
// Layout idea after PiPilot (https://github.com/CikeSeven/pi_pilot), MIT. See THIRD_PARTY_NOTICES.md.
import SwiftUI

enum SettingsMetrics {
    static let inset: CGFloat = 16
    static let trailingInset: CGFloat = 12
    static let icon: CGFloat = 32
    static let iconGlyph: CGFloat = 18
    static let lineGlyph: CGFloat = 20
    static let iconGap: CGFloat = 12
    static let row: CGFloat = 52
    static let detailRow: CGFloat = 64
    static let groupGap: CGFloat = 24
    static let bar: CGFloat = 56
    static let barButton: CGFloat = 44
    static let sheetGutter: CGFloat = 20
}

struct SettingsPage<Content: View>: View {
    let title: LocalizedStringKey
    var showsBack = true
    var showsTitle = true
    var backAction: (() -> Void)?
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @Environment(\.settingsTarget) private var target
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var revealedTarget: String?
    @State private var offset: CGFloat = 0
    @State private var headerHeight: CGFloat = 60
    @Namespace private var scroll

    var body: some View {
        let top = showsBack ? SettingsMetrics.bar : 0
        let barTitle = min(1, max(0, (offset - headerHeight * 0.4) / 20))

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if top > 0 { Color.clear.frame(height: top) }
                    if showsTitle {
                        Text(title).settingsType(.pageTitle)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.horizontal, Space.sm)
                            .padding(.top, 6)
                            .padding(.bottom, Space.xl)
                            .opacity(max(0, 1 - offset / (headerHeight * 0.6)))
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(key: SettingsHeaderHeight.self, value: geometry.size.height)
                                }
                            }
                    }
                    content()
                }
                .foregroundStyle(DS.ink)
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.xxxl)
                .frame(maxWidth: Space.readingWidth)
                .frame(maxWidth: .infinity)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: SettingsScrollOffset.self, value: -geometry.frame(in: .named(scroll)).minY)
                    }
                }
                #if DEBUG
                .overlay {
                    if let offset = DebugPageRegistry.scrollOffset {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: offset)
                            Color.clear.frame(height: 0).id("settings-debug-scroll")
                            Spacer(minLength: 0)
                        }
                        .allowsHitTesting(false)
                    }
                }
                #endif
            }
            .coordinateSpace(name: scroll)
            .scrollIndicators(.hidden)
            .onPreferenceChange(SettingsScrollOffset.self) { offset = $0 }
            .onPreferenceChange(SettingsHeaderHeight.self) { headerHeight = max(40, $0) }
            .onPreferenceChange(SettingsAnchorReady.self) { anchor in
                guard let anchor, anchor == target, anchor != revealedTarget else { return }
                revealedTarget = anchor
                withAnimation(reduceMotion ? nil : AppMotion.standard) {
                    proxy.scrollTo(anchor, anchor: UnitPoint(x: 0.5, y: 1.0 / 3.0))
                }
            }
            #if DEBUG
            .task {
                if DebugPageRegistry.scrollOffset != nil { proxy.scrollTo("settings-debug-scroll", anchor: .top) }
            }
            #endif
        }
        .background { AppBackdrop() }
        .overlay(alignment: .top) {
            if showsBack {
                AppBackdrop()
                    .mask(alignment: .top) {
                        VStack(spacing: 0) {
                            Color.black.frame(height: top)
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: Space.md)
                        }.ignoresSafeArea(edges: .top)
                    }
                    .opacity(min(1, max(0, offset / Space.xxl)))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .top) {
            if showsBack {
                Text(title).settingsType(.titleMedium)
                    .lineLimit(1)
                    .padding(.horizontal, 64)
                    .opacity(barTitle)
                    .offset(y: 6 * (1 - barTitle))
                    .accessibilityHidden(barTitle < 0.9)
                    .frame(height: top)
                    .frame(maxWidth: .infinity)
                HStack {
                    GlassIconButton(glyph: AppIcon.back, label: "Back", size: SettingsMetrics.barButton) {
                        if let backAction { backAction() } else { dismiss() }
                    }
                    Spacer()
                }
                .padding(.horizontal, Space.floatInset)
                .frame(height: top)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct SettingsScrollOffset: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct SettingsHeaderHeight: PreferenceKey {
    static let defaultValue: CGFloat = 60
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension View {
    func settingsType(_ role: TextRole) -> some View { modifier(SettingsTypeStyle(role: role)) }
}

private struct SettingsTypeStyle: ViewModifier {
    let role: TextRole
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content.font(.system(size: role.size * scale, weight: role.weight))
            .lineSpacing(max(0, role.size * scale * (role.height - 1.2)))
            .frame(minHeight: role.size * scale * role.height)
    }
}

struct SheetGroup<Content: View>: View {
    var rowGap: CGFloat = Space.xxs
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: rowGap, content: content)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.xs)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .glass(.card, radius: Radius.lg)
    }
}

struct SettingsGroup<Content: View>: View {
    var header: LocalizedStringKey?
    var footer: LocalizedStringKey?
    var rowGap: CGFloat = Space.xxs
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if let header {
                Text(header).settingsType(.label).tracking(0.1).foregroundStyle(DS.inkFaint)
                    .padding(.horizontal, Space.sm)
                    .accessibilityAddTraits(.isHeader)
            }
            SheetGroup(rowGap: rowGap, content: content)
            if let footer {
                Text(footer).settingsType(.bodySmall).foregroundStyle(DS.inkFaint)
                    .padding(.horizontal, Space.sm)
            }
        }
        .padding(.bottom, SettingsMetrics.groupGap)
    }
}

enum TileTone {
    case ai, ability, neutral, danger, identity(Int)

    var colors: (fill: Color, ink: Color) {
        switch self {
        case .ai: DS.identity[0]
        case .ability: DS.identity[6]
        case .neutral: DS.identity[7]
        case .danger: (DS.dangerContainer, DS.onDangerContainer)
        case .identity(let index): DS.identity[index % DS.identity.count]
        }
    }

    var isDanger: Bool {
        if case .danger = self { return true }
        return false
    }
}

struct SettingsIcon: View {
    let glyph: DshGlyph
    var tone: TileTone = .ai
    var size = SettingsMetrics.icon

    var body: some View {
        Glyph(glyph: glyph, size: size == SettingsMetrics.icon ? SettingsMetrics.iconGlyph : size * 0.46)
            .foregroundStyle(tone.colors.ink)
            .frame(width: size, height: size)
            .background(tone.colors.fill, in: Circle())
    }
}

struct SettingsLineIcon: View {
    let glyph: DshGlyph
    var danger = false

    var body: some View {
        Glyph(glyph: glyph, size: SettingsMetrics.lineGlyph)
            .foregroundStyle(danger ? DS.danger : DS.inkMuted)
            .frame(width: SettingsMetrics.icon, height: SettingsMetrics.icon)
    }
}

struct SettingsRow<Trailing: View>: View {
    var glyph: DshGlyph?
    var tone: TileTone = .ai
    let title: LocalizedStringKey
    var subtitle: String?
    var titleColor: Color = DS.ink
    var verbatim: String?
    var tinted = false
    var value: String?
    var valueColor: Color = DS.inkMuted
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            if let glyph {
                Group {
                    if tinted { SettingsIcon(glyph: glyph, tone: tone) }
                    else { SettingsLineIcon(glyph: glyph, danger: tone.isDanger) }
                }
                .padding(.trailing, SettingsMetrics.iconGap)
            }
            VStack(alignment: .leading, spacing: 1) {
                Group { if let verbatim { Text(verbatim: verbatim) } else { Text(title) } }
                    .settingsType(.setting).foregroundStyle(tone.isDanger ? DS.danger : titleColor)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).settingsType(.bodySmall).foregroundStyle(DS.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            if let value, !value.isEmpty {
                Text(value).monospacedDigit().settingsType(.bodyMedium).foregroundStyle(valueColor)
                    .multilineTextAlignment(.trailing).lineLimit(2).padding(.leading, Space.md)
            }
            trailing()
                .padding(.leading, Trailing.self == SettingsChevron.self ? Space.xs : Space.sm)
        }
        .padding(.leading, SettingsMetrics.inset)
        .padding(.trailing, Trailing.self == EmptyView.self ? SettingsMetrics.inset : SettingsMetrics.trailingInset)
        .padding(.vertical, 6)
        .frame(minHeight: subtitle?.isEmpty == false ? SettingsMetrics.detailRow : SettingsMetrics.row)
        .contentShape(Rectangle())
    }
}

extension SettingsRow where Trailing == SettingsChevron {
    init(glyph: DshGlyph? = nil, tone: TileTone = .ai, title: LocalizedStringKey, subtitle: String? = nil,
         tinted: Bool = false, value: String? = nil, valueColor: Color = DS.inkMuted) {
        self.init(glyph: glyph, tone: tone, title: title, subtitle: subtitle, tinted: tinted, value: value, valueColor: valueColor) { SettingsChevron() }
    }
}

struct SettingsChevron: View {
    var body: some View {
        Glyph(glyph: AppIcon.disclosure, size: 20)
            .foregroundStyle(DS.inkFaint)
            .offset(x: 3)
    }
}

struct InfoRow: View {
    let label: LocalizedStringKey
    let value: String
    var mono = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.lg) {
            Text(label).settingsType(.setting).foregroundStyle(DS.ink)
            Group {
                if mono { Text(value).font(Mono.font(12)) }
                else { Text(value).monospacedDigit().settingsType(.bodyMedium) }
            }
            .foregroundStyle(DS.inkMuted)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, SettingsMetrics.inset)
        .padding(.vertical, 6)
        .frame(minHeight: SettingsMetrics.row)
        .accessibilityElement(children: .combine)
    }
}

/// Hairline between rows inside a group card.
struct RowDivider: View {
    var inset: CGFloat = 16
    var body: some View { Rectangle().fill(DS.rule.opacity(0.8)).frame(height: 0.5).padding(.leading, inset) }
}

struct SettingsLink<Destination: View>: View {
    var glyph: DshGlyph?
    var tone: TileTone = .ai
    let title: LocalizedStringKey
    var subtitle: String?
    var tinted = false
    var value: String?
    @ViewBuilder let destination: () -> Destination
    var body: some View {
        NavigationLink(destination: destination) {
            SettingsRow(glyph: glyph, tone: tone, title: title, subtitle: subtitle, tinted: tinted, value: value)
        }
        .buttonStyle(SettingsPressStyle())
    }
}

struct SettingsToggleRow: View {
    var glyph: DshGlyph?
    var tone: TileTone = .ai
    let title: LocalizedStringKey
    var subtitle: String?
    var tinted = false
    let isOn: Binding<Bool>
    var body: some View {
        Toggle(isOn: isOn) {
            SettingsRow(glyph: glyph, tone: tone, title: title, subtitle: subtitle, tinted: tinted) {
                MistSwitch(isOn: isOn.wrappedValue)
            }
        }
        .toggleStyle(SettingsRowToggleStyle())
    }
}

private struct SettingsRowToggleStyle: ToggleStyle {
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var clicks = 0

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
            clicks += 1
        } label: {
            configuration.label
        }
        .buttonStyle(SettingsPressStyle())
        .accessibilityValue(Text(configuration.isOn ? "On" : "Off"))
        .sensoryFeedback(.selection, trigger: clicks)
        .animation(reduceMotion ? nil : AppMotion.quick, value: configuration.isOn)
    }
}

struct SettingsChoiceRow: View {
    @Environment(\.designTheme) private var theme
    let title: String
    var subtitle: String?
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            SettingsRow(title: "", subtitle: subtitle, verbatim: title) {
                if selected { Glyph(glyph: DshGlyph.check, size: 18).foregroundStyle(theme.accent) }
            }
        }
        .buttonStyle(SettingsPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct MistSwitch: View {
    let isOn: Bool
    @Environment(\.designTheme) private var theme
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? theme.accent.opacity(enabled ? 1 : 0.38) : DS.switchTrack.opacity(enabled ? 1 : 0.41))
                .frame(width: 52, height: 32)
            Circle().fill(DS.switchKnob.opacity(enabled ? 1 : 0.5))
                .frame(width: 24, height: 24)
                .overlay {
                    if isOn { Glyph(glyph: .check, size: 14).foregroundStyle(theme.accentCheck) }
                }
                .padding(.horizontal, Space.xs)
        }
        .padding(.horizontal, Space.xs)
        .accessibilityHidden(true)
    }
}

/// The transparent off-state icon in Material keeps both knobs at 24 points.
struct MistToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            MistSwitch(isOn: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: Binding(get: { configuration.isOn }, set: { configuration.isOn = $0 })) {
                configuration.label
            }.toggleStyle(.switch)
        }
        .sensoryFeedback(.selection, trigger: configuration.isOn)
    }
}

struct SettingsPressStyle: ButtonStyle {
    var scales = false
    @Environment(\.appReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(DS.ink.opacity(configuration.isPressed && !scales ? 0.05 : 0))
            .scaleEffect(configuration.isPressed && scales && !reduceMotion ? AppMotion.pressScale : 1)
            .animation(reduceMotion ? nil : AppMotion.press, value: configuration.isPressed)
    }
}

/// Full-width primary / secondary buttons.
struct MistButton: View {
    @Environment(\.designTheme) private var theme
    enum Kind { case primary, secondary, danger }
    let title: LocalizedStringKey
    var kind = Kind.primary
    var busy = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Group { if busy { ProgressView().tint(kind == .primary ? theme.onAccent : DS.ink) } else { Text(title) } }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(kind == .primary ? theme.onAccent : kind == .danger ? DS.danger : DS.ink)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(kind == .primary ? theme.accent : .clear)
                    if kind != .primary {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(DS.outline.opacity(0.55))
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
