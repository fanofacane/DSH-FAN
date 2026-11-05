// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/lib/ui/chat/{usage_sheet,composer}.dart.
import DSHClient
import SwiftUI

struct ContextRing: View {
    let fraction: Double
    let open: () -> Void
    @Environment(\.designTheme) private var theme

    var body: some View {
        let tone = theme.contextTone(fraction)
        Button(action: open) {
            HStack(spacing: Space.xs) {
                ZStack {
                    Circle().stroke(DS.capsuleTrack, lineWidth: 2.2)
                    Circle().trim(from: 0, to: max(0.02, fraction))
                        .stroke(tone, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: RunLayout.contextRing, height: RunLayout.contextRing)
                Text(verbatim: RunFormat.percent(fraction)).font(Mono.font(12, weight: .medium))
                    .foregroundStyle(fraction >= 0.6 ? tone : DS.inkFaint)
            }
            .padding(.horizontal, Space.xs)
            .frame(minHeight: RunLayout.composerButton)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Context used: \(RunFormat.percent(fraction))"))
        .accessibilityIdentifier("context-usage")
    }
}

struct UsagePanel: View {
    let metrics: SessionMetrics
    let turns: [TurnTrace]
    let historyHasMore: Bool
    let host: String
    let model: String?
    let engine: String?
    let balance: RunBalance?
    @Binding var balanceLimit: Double
    let openTrace: (TurnTrace) -> Void
    @Environment(\.designTheme) private var theme
    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 0) {
            RunPanelHeader(title: Text("Usage"))
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    context
                    tokens
                    if let balance { RunBalanceCard(balance: balance, limit: $balanceLimit) }
                    details
                }
                .padding(.horizontal, RunLayout.panelInset)
                .padding(.bottom, Space.xl)
            }
        }
        .background(DS.surface)
        .accessibilityIdentifier("usage-panel")
    }

    private var context: some View {
        RunPanelSection(title: "Context") {
            if let fraction = metrics.fraction, let used = metrics.pressureTokens, let window = metrics.contextWindow {
                HStack(alignment: .firstTextBaseline) {
                    RunFigure(value: RunFormat.percent(fraction), size: RunLayout.usageHeadline,
                              color: fraction >= 0.6 ? theme.contextTone(fraction) : DS.ink)
                    Spacer()
                    Text(verbatim: "\(RunFormat.tokens(used)) / \(RunFormat.tokens(window))")
                        .type(.bodySmall).monospacedDigit().foregroundStyle(DS.inkMuted)
                }
                GeometryReader { geometry in
                    let width = geometry.size.width
                    Capsule().fill(DS.capsuleTrack)
                        .overlay(alignment: .leading) {
                            Capsule().fill(theme.contextTone(fraction))
                                .frame(width: min(width, fraction == 0 ? 0 : max(6, width * fraction)))
                        }
                }
                .frame(height: RunLayout.usageBarHeight)
                Text(breakdown).type(.bodySmall).monospacedDigit().foregroundStyle(DS.inkFaint)
                if fraction >= 0.85 {
                    Text("Context nearly full. Send /compact to compress it.")
                        .type(.bodySmall).foregroundStyle(DS.warn)
                }
            } else {
                Text("Context usage not reported").type(.bodyMedium).foregroundStyle(DS.inkFaint)
            }
        }
    }

    private var breakdown: String {
        [String(localized: "System \(RunPanelValue.tokens(metrics.systemTokens))"),
         String(localized: "Tools \(RunPanelValue.tokens(metrics.toolTokens))"),
         String(localized: "Messages \(RunPanelValue.tokens(metrics.messageTokens))")].joined(separator: " · ")
    }

    private var tokens: some View {
        RunPanelSection(title: "This chat") {
            HStack(alignment: .top, spacing: Space.sm) {
                RunPanelStat(label: "Input", value: RunPanelValue.tokens(metrics.input))
                RunPanelStat(label: "Output", value: RunPanelValue.tokens(metrics.output))
                RunPanelStat(label: "Cache hit", value: RunPanelValue.percent(metrics.cacheHitRate))
            }
            Text(usageNotes).type(.bodySmall).foregroundStyle(DS.inkFaint)
        }
    }

    private var usageNotes: String {
        let count = metrics.turns.map { String(localized: "\($0) turns in total") } ?? String(localized: "Turn count not reported")
        var parts = [count]
        if let write = metrics.cacheWrite, write > 0 { parts.append(String(localized: "Cache writes \(RunFormat.tokens(write))")) }
        if let cost = RunPricing.sessionEstimate(turns, metrics: metrics) { parts.append(RunFormat.cost(cost)) }
        parts.append(String(localized: "Input includes cache hits"))
        return parts.joined(separator: " · ")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            DisclosureGroup("Run details", isExpanded: $showDetails) {
                VStack(spacing: 0) {
                    InfoRow(label: "Host", value: host)
                    InfoRow(label: "Selected model", value: model ?? RunPanelValue.unreported)
                    if let engine { InfoRow(label: "Local engine", value: engine) }
                    InfoRow(label: "Next request estimate", value: RunPanelValue.tokens(metrics.projectedTokens))
                    InfoRow(label: "Uncached input", value: RunPanelValue.tokens(metrics.uncached))
                    InfoRow(label: "Cache reads", value: RunPanelValue.tokens(metrics.cacheRead))
                    InfoRow(label: "Cache writes", value: RunPanelValue.tokens(metrics.cacheWrite))
                    InfoRow(label: "Model time", value: RunFormat.duration(metrics.modelMs.map { Double($0) / 1000 }))
                    InfoRow(label: "Tool time", value: RunFormat.duration(metrics.toolMs.map { Double($0) / 1000 }))
                    if historyHasMore { Text("Showing recent history only.").type(.bodySmall).foregroundStyle(DS.inkFaint).padding(Space.sm) }
                }
            }
            .type(.bodyMedium)
            .tint(theme.accent)
            .sensoryFeedback(.selection, trigger: showDetails)
            if let turn = turns.last {
                Button { openTrace(turn) } label: {
                    HStack {
                        Text("Latest trajectory").type(.bodyMedium)
                        Spacer()
                        Glyph(glyph: AppIcon.disclosure, size: 16)
                    }
                    .foregroundStyle(theme.accent)
                    .frame(minHeight: RunLayout.actionSize).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Space.sm)
    }
}

enum RunPanelValue {
    static var unreported: String { String(localized: "Not reported") }
    static func tokens(_ value: Int?) -> String { value.map(RunFormat.tokens) ?? unreported }
    static func percent(_ value: Double?) -> String { value.map(RunFormat.percent) ?? unreported }
}

struct RunPanelHeader: View {
    let title: Text
    var note: Text?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                title.type(.hero).foregroundStyle(DS.ink)
                    .accessibilityAddTraits(.isHeader)
                if let note { note.type(.bodySmall).foregroundStyle(DS.inkFaint) }
            }
            .padding(.top, Space.sm)
            Spacer(minLength: 0)
            GlassIconButton(glyph: AppIcon.close, label: "Close", size: 36) { dismiss() }
        }
        .padding(.horizontal, RunLayout.panelInset)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.sm)
    }
}

struct RunPanelSection<Content: View>: View {
    var title: LocalizedStringKey?
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let title {
                Text(title).type(.labelMedium).foregroundStyle(DS.inkFaint)
                    .padding(.horizontal, Space.sm).accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: Space.sm, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.lg)
                .padding(.vertical, 14)
                .glass(.card, radius: Radius.lg)
        }
    }
}

struct RunPanelStat: View {
    let label: LocalizedStringKey
    let value: String
    var size: CGFloat = RunLayout.usageValue
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            RunFigure(value: value, size: size)
            Text(label).type(.bodySmall).foregroundStyle(DS.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct RunFigure: View {
    let value: String
    let size: CGFloat
    var color: Color = DS.ink
    var body: some View {
        let digits = value.range(of: #"[<\d][\d.,:]*"#, options: .regularExpression)
        Group {
            if let range = digits {
                Text("\(unit(String(value[..<range.lowerBound])))\(number(String(value[range])))\(unit(String(value[range.upperBound...])))")
            } else {
                Text(verbatim: value).font(.system(size: size * 0.6)).foregroundStyle(DS.inkFaint)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private func unit(_ text: String) -> Text {
        Text(verbatim: text).font(.system(size: size * 0.65)).foregroundColor(DS.inkMuted)
    }

    private func number(_ text: String) -> Text {
        Text(verbatim: text).font(.system(size: size, weight: .medium).monospacedDigit()).foregroundColor(color)
    }
}
