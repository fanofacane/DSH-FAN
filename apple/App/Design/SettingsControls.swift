// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/common/{segmented_pill,search_capsule,status_dot,status_chip,capsule_chip}.dart,
// and ui/settings/settings_widgets.dart (SettingsSegmentTile).
import SwiftUI

struct PillSegment<Value: Hashable>: Identifiable {
    let id: Value
    let label: String

    init(_ id: Value, _ label: String) {
        self.id = id
        self.label = label
    }
}

struct SettingsSegmentRow<Value: Hashable>: View {
    var glyph: DshGlyph?
    var tone: TileTone = .ai
    var tinted = false
    let title: LocalizedStringKey
    let segments: [PillSegment<Value>]
    let selection: Binding<Value>

    var body: some View {
        let leading = glyph == nil ? 0 : SettingsMetrics.icon + SettingsMetrics.iconGap
        SegmentRowLayout(leading: leading) {
            HStack(spacing: SettingsMetrics.iconGap) {
                if let glyph {
                    if tinted { SettingsIcon(glyph: glyph, tone: tone) }
                    else { SettingsLineIcon(glyph: glyph) }
                }
                Text(title).settingsType(.setting)
            }
            SegmentedPill(segments: segments, selection: selection)
        }
        .padding(.horizontal, SettingsMetrics.inset)
        .padding(.vertical, Space.sm)
    }
}

struct SegmentRowLayout: Layout {
    let leading: CGFloat

    static func fitsInline(title: CGFloat, pill: CGFloat, available: CGFloat) -> Bool {
        title + Space.lg + pill <= available
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let title = subviews[0].sizeThatFits(.unspecified)
        let pill = subviews[1].sizeThatFits(.unspecified)
        let width = proposal.width ?? (title.width + Space.lg + pill.width)
        if Self.fitsInline(title: title.width, pill: pill.width, available: width) {
            return CGSize(width: width, height: max(SettingsMetrics.row - 2 * Space.sm, title.height, pill.height))
        }
        let wrapped = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: width, height: max(SettingsMetrics.icon, wrapped.height) + Space.sm + Space.xs + 2 + pill.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let title = subviews[0].sizeThatFits(.unspecified)
        let pill = subviews[1].sizeThatFits(.unspecified)
        if Self.fitsInline(title: title.width, pill: pill.width, available: bounds.width) {
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: .unspecified)
            subviews[1].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing,
                              proposal: ProposedViewSize(pill))
        } else {
            let titleProposal = ProposedViewSize(width: bounds.width, height: nil)
            let titleHeight = max(SettingsMetrics.icon, subviews[0].sizeThatFits(titleProposal).height)
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY + titleHeight / 2),
                              anchor: .leading, proposal: titleProposal)
            subviews[1].place(at: CGPoint(x: bounds.minX + leading, y: bounds.minY + titleHeight + 10),
                              proposal: ProposedViewSize(width: max(0, bounds.width - leading), height: pill.height))
        }
    }
}

struct SegmentedPill<Value: Hashable>: View {
    let segments: [PillSegment<Value>]
    let selection: Binding<Value>
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 13.5
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @GestureState private var drag: CGFloat? = nil
    @State private var ticks = 0

    private let inset: CGFloat = 3
    private var selected: Int { segments.firstIndex { $0.id == selection.wrappedValue } ?? 0 }
    private var naturalWidth: CGFloat {
        let font = UIFont.systemFont(ofSize: labelSize, weight: .semibold)
        let widest = segments.map { ($0.label as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return ceil(widest + 28) * CGFloat(segments.count) + 2 * inset
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, (geometry.size.width - 2 * inset) / CGFloat(segments.count))
            let position = min(CGFloat(segments.count - 1), max(0, CGFloat(selected) + (drag ?? 0) / width))
            let active = Int(position.rounded())
            ZStack(alignment: .leading) {
                Capsule().fill(DS.capsuleTrack)
                Capsule().fill(DS.segmentThumb)
                    .shadow(color: scheme == .light ? .black.opacity(0.08) : .clear, radius: 3, y: 1)
                    .frame(width: width)
                    .padding(.vertical, inset)
                    .offset(x: inset + position * width)
                    .animation(drag == nil && !reduceMotion ? AppMotion.thumb : nil, value: position)
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        Button { select(index) } label: {
                            Text(segment.label)
                                .font(.system(size: labelSize, weight: active == index ? .semibold : .medium))
                                .tracking(0.1).lineLimit(1).minimumScaleFactor(0.35)
                                .foregroundStyle(active == index ? DS.ink : DS.inkMuted)
                                .padding(.horizontal, 6)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(index == selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, inset)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .updating($drag) { value, state, _ in
                        if abs(value.translation.width) > abs(value.translation.height) { state = value.translation.width }
                    }
                    .onEnded { value in
                        guard enabled, abs(value.translation.width) > abs(value.translation.height) else { return }
                        let index = selected + Int((value.translation.width / width).rounded())
                        select(min(segments.count - 1, max(0, index)), feedback: reduceMotion)
                    }
            )
            .onChange(of: active) { _, _ in
                if drag != nil && !reduceMotion { ticks += 1 }
            }
        }
        .frame(height: max(36, labelSize * 1.2 + 2 * inset + 14))
        .frame(idealWidth: naturalWidth)
        .opacity(enabled ? 1 : 0.5)
        .sensoryFeedback(.selection, trigger: ticks)
    }

    private func select(_ index: Int, feedback: Bool = true) {
        let value = segments[index].id
        guard enabled, value != selection.wrappedValue else { return }
        selection.wrappedValue = value
        if feedback { ticks += 1 }
    }
}

struct SearchCapsule: View {
    let hint: LocalizedStringKey
    @Binding var query: String
    var autoFocus = false
    @FocusState private var focused: Bool

    var body: some View {
        SearchCapsuleShape {
            TextField("", text: $query, prompt: Text(hint).foregroundStyle(DS.inkFaint))
                .foregroundStyle(DS.ink)
                .submitLabel(.search).focused($focused)
                .autocorrectionDisabled()
                .accessibilityLabel(Text(hint))
            Button {
                query = ""
                focused = true
            } label: {
                Glyph(glyph: AppIcon.close, size: 18).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Clear"))
            .opacity(query.isEmpty ? 0 : 1)
            .disabled(query.isEmpty)
        }
        .task { if autoFocus { focused = true } }
    }
}

struct SearchCapsuleShape<Content: View>: View {
    @ScaledMetric(relativeTo: .body) private var textSize: CGFloat = 14
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            Glyph(glyph: AppIcon.search, size: 20).frame(width: 44)
                .padding(.trailing, Space.xs)
            content()
        }
        .font(.system(size: textSize))
        .foregroundStyle(DS.inkFaint)
        .frame(height: max(44, textSize * 1.55 + 22))
        .background(DS.searchFill, in: Capsule())
    }
}

enum StatusTone: Equatable {
    case ok, busy, warn, error, idle

    func color(theme: DesignTheme) -> Color {
        switch self {
        case .ok: DS.success
        case .busy: theme.accent
        case .warn: DS.warn
        case .error: DS.danger
        case .idle: DS.outline
        }
    }
}

struct StatusDot: View {
    let tone: StatusTone
    var size: CGFloat = 8
    @Environment(\.designTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Circle().fill(tone.color(theme: theme))
            .frame(width: size, height: size)
            .opacity(dimmed ? 0.35 : 1)
            .animation(reduceMotion ? nil : AppMotion.standard, value: tone)
            .task(id: tone == .busy && !reduceMotion) {
                let pulse = tone == .busy && !reduceMotion
                withAnimation(pulse ? AppMotion.breath : nil) { dimmed = pulse }
            }
            .accessibilityHidden(true)
    }
}

struct StatusChip: View {
    let tone: StatusTone
    let label: LocalizedStringKey
    @Environment(\.designTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ink: Color {
        switch tone {
        case .ok: scheme == .dark ? DS.onSuccessContainer : DS.success
        case .warn: scheme == .dark ? DS.onWarnContainer : DS.warn
        case .error: scheme == .dark ? DS.onDangerContainer : DS.danger
        case .busy: scheme == .dark ? theme.onAccentContainer : theme.accent
        case .idle: DS.inkFaint
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(tone: tone, size: 6)
            Text(label).monospacedDigit().settingsType(.labelMedium).lineLimit(1)
                .contentTransition(.opacity)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 10)
        .frame(minHeight: 24)
        .background(tone == .idle ? DS.capsuleTrack : tone.color(theme: theme).opacity(scheme == .dark ? 0.2 : 0.12),
                    in: Capsule())
        .animation(reduceMotion ? nil : AppMotion.standard, value: tone)
    }
}

struct CapsuleChoiceChip: View {
    let label: LocalizedStringKey
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? DS.surface : DS.inkMuted)
                .padding(.horizontal, 12).frame(minHeight: 32)
                .background(selected ? DS.ink : DS.searchFill, in: Capsule())
        }
        .buttonStyle(SettingsPressStyle(scales: true))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
