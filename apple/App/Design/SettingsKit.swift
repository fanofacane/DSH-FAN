// SPDX-License-Identifier: AGPL-3.0-or-later
// Settings building blocks in the Mist Glass style of 原 Flutter 版 lib/ui/settings
// (page_frame, settings tiles, glass group cards). Reference:
// 原 Flutter 版 test/settings/goldens/settings_signed_in_light.png, personalization_light.png.
import SwiftUI

/// Full page: backdrop, glass back button, large title, scrolling content.
struct SettingsPage<Content: View>: View {
    let title: LocalizedStringKey
    var showsBack = true
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            AppBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: showsBack ? 56 : 8)
                    Text(title).font(.system(size: 30, weight: .bold)).foregroundStyle(DS.ink)
                        .padding(.horizontal, 8).padding(.bottom, 18)
                    content()
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, 40)
                .frame(maxWidth: Space.readingWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            if showsBack {
                GlassIconButton(glyph: AppIcon.back, label: "Back") { dismiss() }
                    .padding(.leading, 12).padding(.top, 4)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Section header + glass card holding rows separated by hairlines.
struct SettingsGroup<Content: View>: View {
    @Environment(\.designTheme) private var theme
    var header: LocalizedStringKey?
    var footer: LocalizedStringKey?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let header {
                Text(header).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.inkFaint).padding(.leading, 8)
            }
            VStack(spacing: 0) { content() }
                .glass(.card, radius: Radius.lg)
            if let footer {
                Text(footer).type(.bodySmall).foregroundStyle(DS.inkFaint).padding(.horizontal, 8)
            }
        }
        .padding(.bottom, 22)
    }
}

enum TileTone {
    case ai, ability, neutral, danger
    func fill(theme: DesignTheme) -> Color {
        switch self {
        case .ai: theme.accentContainer
        case .ability: DS.warnContainer
        case .neutral: DS.surfaceHigh
        case .danger: DS.dangerContainer
        }
    }
    func tint(theme: DesignTheme) -> Color {
        switch self {
        case .ai: theme.onAccentContainer
        case .ability: DS.warn
        case .neutral: DS.inkMuted
        case .danger: DS.danger
        }
    }
}

/// One settings row: optional round icon, title, subtitle, trailing accessory.
struct SettingsRow<Trailing: View>: View {
    @Environment(\.designTheme) private var theme
    var glyph: DshGlyph?
    var tone: TileTone = .ai
    let title: LocalizedStringKey
    var subtitle: String?
    var titleColor: Color = DS.ink
    /// Untranslated text (names, accounts); shown as-is instead of `title`.
    var verbatim: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            if let glyph {
                Glyph(glyph: glyph, size: 20).foregroundStyle(tone.tint(theme: theme))
                    .frame(width: 40, height: 40).background(tone.fill(theme: theme), in: Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Group { if let verbatim { Text(verbatim: verbatim) } else { Text(title) } }
                    .font(.system(size: 16)).foregroundStyle(titleColor)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(DS.inkFaint).lineLimit(3)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, glyph == nil ? 14 : 12)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

extension SettingsRow where Trailing == SettingsChevron {
    init(glyph: DshGlyph? = nil, tone: TileTone = .ai, title: LocalizedStringKey, subtitle: String? = nil) {
        self.init(glyph: glyph, tone: tone, title: title, subtitle: subtitle) { SettingsChevron() }
    }
}

struct SettingsChevron: View {
    var body: some View { Glyph(glyph: DshGlyph.caretRight, size: 18).foregroundStyle(DS.inkFaint) }
}

/// Hairline between rows inside a group card.
struct RowDivider: View {
    var inset: CGFloat = 16
    var body: some View { Rectangle().fill(DS.rule.opacity(0.8)).frame(height: 0.5).padding(.leading, inset) }
}

/// A navigation row that pushes `destination`.
struct SettingsLink<Destination: View>: View {
    var glyph: DshGlyph?
    var tone: TileTone = .ai
    let title: LocalizedStringKey
    var subtitle: String?
    @ViewBuilder let destination: () -> Destination
    var body: some View {
        NavigationLink(destination: destination) {
            SettingsRow(glyph: glyph, tone: tone, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }
}

/// A row with the Mist toggle on the right.
struct SettingsToggleRow: View {
    var glyph: DshGlyph?
    var tone: TileTone = .ai
    let title: LocalizedStringKey
    var subtitle: String?
    let isOn: Binding<Bool>
    var body: some View {
        SettingsRow(glyph: glyph, tone: tone, title: title, subtitle: subtitle) {
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(MistToggleStyle())
        }
    }
}

/// A row in a single-choice list: checkmark on the selected one.
struct SettingsChoiceRow: View {
    @Environment(\.designTheme) private var theme
    let title: String
    var subtitle: String?
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            SettingsRow(title: LocalizedStringKey(title), subtitle: subtitle) {
                if selected { Glyph(glyph: DshGlyph.check, size: 18).foregroundStyle(theme.accent) }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Accent capsule with a white knob carrying a check (Flutter's Switch theme).
struct MistToggleStyle: ToggleStyle {
    @Environment(\.designTheme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        Button { withAnimation(.snappy(duration: 0.2)) { configuration.isOn.toggle() } } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? theme.accent : DS.surfaceHigh)
                    .overlay(Capsule().strokeBorder(configuration.isOn ? .clear : DS.outline.opacity(0.7), lineWidth: 1.5))
                    .frame(width: 52, height: 32)
                Circle().fill(configuration.isOn ? Color.white : DS.outline)
                    .frame(width: configuration.isOn ? 24 : 16, height: configuration.isOn ? 24 : 16)
                    .overlay {
                        if configuration.isOn { Glyph(glyph: DshGlyph.check, size: 14).foregroundStyle(theme.accent) }
                    }
                    .padding(.horizontal, configuration.isOn ? 4 : 8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(configuration.isOn ? "On" : "Off"))
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
            Group { if busy { ProgressView().tint(kind == .primary ? DS.onAccent : DS.ink) } else { Text(title) } }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(kind == .primary ? DS.onAccent : kind == .danger ? DS.danger : DS.ink)
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
