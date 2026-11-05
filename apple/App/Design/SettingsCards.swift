// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/common/{overview_card,page_hero,app_sheet,risk_notice,expand_reveal,brief_notice}.dart.
import SwiftUI

struct OverviewCard<Leading: View, Accessory: View, Footer: View>: View {
    let title: Text
    var subtitle: Text?
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let footer: () -> Footer
    var open: (() -> Void)?
    var openFooter: (() -> Void)?

    static var avatar: CGFloat { 52 }
    static var gap: CGFloat { 14 }

    var body: some View {
        VStack(spacing: 0) {
            if let open {
                Button(action: open) { heading }.buttonStyle(SettingsPressStyle(scales: true))
            } else {
                heading
            }
            if Footer.self != EmptyView.self {
                Rectangle().fill(DS.ink.opacity(0.08)).frame(height: 0.5).padding(.horizontal, Space.lg)
                if let openFooter {
                    Button(action: openFooter) { footerRow }.buttonStyle(SettingsPressStyle())
                } else {
                    footerRow
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .glass(.card, radius: Radius.lg)
        .padding(.bottom, SettingsMetrics.groupGap)
    }

    private var heading: some View {
        HStack(spacing: Self.gap) {
            leading().frame(width: Self.avatar, height: Self.avatar)
            VStack(alignment: .leading, spacing: Space.xxs) {
                title.settingsType(.titleMedium).foregroundStyle(DS.ink).lineLimit(1)
                if let subtitle {
                    subtitle.monospacedDigit().settingsType(.bodyMedium).foregroundStyle(DS.inkMuted).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                if Accessory.self != EmptyView.self { accessory() }
                else if open != nil { SettingsChevron() }
            }
        }
        .padding(.leading, SettingsMetrics.inset)
        .padding(.trailing, SettingsMetrics.trailingInset)
        .padding(.vertical, Space.lg)
        .contentShape(Rectangle())
    }

    private var footerRow: some View {
        HStack(spacing: Space.xs) {
            footer().frame(maxWidth: .infinity, alignment: .leading)
            if openFooter != nil { SettingsChevron() }
        }
        .padding(.trailing, SettingsMetrics.trailingInset)
        .padding(.vertical, Space.sm)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct OverviewFooter: View {
    let tone: StatusTone
    let text: Text

    var body: some View {
        HStack(spacing: 14) {
            StatusDot(tone: tone)
                .frame(width: 52)
                .padding(.leading, SettingsMetrics.inset)
            text.monospacedDigit().settingsType(.bodySmall).foregroundStyle(DS.inkMuted)
                .lineLimit(1).contentTransition(.opacity)
        }
    }
}

struct PageHero<Leading: View, Trailing: View>: View {
    let title: Text
    var subtitle: Text?
    var stats: [(value: String, label: LocalizedStringKey)] = []
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            HStack(spacing: Space.lg) {
                leading()
                VStack(alignment: .leading, spacing: Space.xxs) {
                    title.settingsType(.hero).lineLimit(2).accessibilityAddTraits(.isHeader)
                    if let subtitle { subtitle.settingsType(.bodyMedium).foregroundStyle(DS.inkFaint).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing()
            }
            if !stats.isEmpty {
                HStack(alignment: .top, spacing: Space.md) {
                    ForEach(stats.indices, id: \.self) { index in
                        let stat = stats[index]
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(stat.value).monospacedDigit().settingsType(.title).lineLimit(1)
                            Text(stat.label).settingsType(.bodySmall).foregroundStyle(DS.inkFaint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.xl)
    }
}

struct SettingsSheet<Content: View>: View {
    let title: LocalizedStringKey
    var locked = false
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Space.md) {
            HStack(spacing: Space.sm) {
                Text(title).settingsType(.title).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if locked {
                    GlassIconButton(glyph: AppIcon.close, label: "Close", size: 36) { dismiss() }
                }
            }
            content()
        }
        .foregroundStyle(DS.ink)
        .padding(.horizontal, SettingsMetrics.sheetGutter)
        .padding(.top, locked ? Space.md : Space.xxl)
        .padding(.bottom, Space.lg)
        // UIKit owns sheet presentation and dismissal, including keyboard and VoiceOver gestures.
        .presentationCornerRadius(Radius.xl)
        .presentationBackground(.regularMaterial)
        .presentationDragIndicator(locked ? .hidden : .visible)
        .interactiveDismissDisabled(locked)
    }
}

struct RiskNoticeSheet: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let action: LocalizedStringKey
    var high = true
    let proceed: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.designTheme) private var theme
    @State private var silence = true

    var body: some View {
        SettingsSheet(title: title, locked: true) {
            ScrollView {
                Text(message).settingsType(.body).foregroundStyle(DS.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !high {
                    Toggle("Don’t show again", isOn: $silence).settingsType(.bodyMedium)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            Button {
                proceed(!high && silence)
                dismiss()
            } label: {
                Text(action).settingsType(.label)
                    .foregroundStyle(high ? DS.onDanger : DS.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(high ? DS.danger : theme.accent, in: Capsule())
            }
            .buttonStyle(SettingsPressStyle(scales: true))
        }
        .presentationDetents([.medium, .large])
    }
}

struct ExpandReveal<Content: View>: View {
    let open: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if open {
                content()
                    .transition(.opacity.combined(with: .offset(y: -Space.sm)))
            }
        }
        .clipped()
        .animation(reduceMotion ? nil : AppMotion.collapse, value: open)
    }
}

struct BriefNotice: View {
    @Binding var text: String?

    var body: some View {
        if let message = text {
            Button { text = nil } label: {
                Text(message).settingsType(.bodyMedium)
                    .foregroundStyle(DS.ink)
                    .padding(.horizontal, Space.lg).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glass(.sheet)
            }
            .buttonStyle(.plain)
            .task(id: message) {
                let units = message.unicodeScalars.reduce(0) { $0 + ($1.value >= 0x2E80 ? 2 : 1) }
                do {
                    try await Task.sleep(for: .milliseconds(min(2000, max(1000, 700 + units * 30))))
                    if text == message { text = nil }
                } catch is CancellationError { }
                catch { }
            }
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}
