// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/lib/ui/chat/{trajectory_sheet,run_info}.dart.
import DSHClient
import SwiftUI

struct TrajectoryPanel: View {
    let trace: TurnTrace?
    let skew: TimeInterval
    let openStep: (TraceStep) -> Void
    @Environment(\.designTheme) private var theme
    @State private var expanded: Set<TraceSpan.ID> = []
    @State private var nearTail = true

    var body: some View {
        Group {
            if let trace {
                LiveRunClock(since: trace.running ? trace.start : nil, skew: skew) { now in
                    contents(trace, now: now)
                }
            } else {
                VStack(alignment: .leading, spacing: Space.md) {
                    RunPanelHeader(title: Text("Turn trajectory"))
                    Text("This turn hasn’t been loaded").type(.bodyMedium).foregroundStyle(DS.inkFaint)
                        .padding(.horizontal, RunLayout.panelInset)
                    Spacer()
                }
            }
        }
        .background(DS.surface)
        .accessibilityIdentifier("trajectory-panel")
    }

    private func contents(_ trace: TurnTrace, now: Date) -> some View {
        let total = trace.duration ?? (trace.running ? max(0, now.timeIntervalSince(trace.start)) : 0)
        let title = trace.running ? RunFormat.clock(total) : RunFormat.duration(trace.duration)
        return VStack(spacing: 0) {
            RunPanelHeader(title: Text("Turn trajectory  \(Text(verbatim: title).foregroundColor(DS.inkMuted))"),
                           note: status(trace))
            composition(trace, total: total)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        let rows = TrajectoryEntry.group(trace.spans)
                        if rows.isEmpty {
                            Text("No timed steps in this turn").type(.bodySmall).foregroundStyle(DS.inkFaint)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(Space.md)
                        }
                        ForEach(rows) { row in
                            if row.spans.count == 1, let span = row.spans.first {
                                tile(span, trace: trace, total: total, now: now)
                            } else {
                                group(row, trace: trace, total: total, now: now)
                            }
                        }
                        Color.clear.frame(height: Space.sm).id("trace-tail")
                            .onAppear { nearTail = true }
                            .onDisappear { nearTail = false }
                    }
                }
                .onAppear { if trace.running { proxy.scrollTo("trace-tail", anchor: .bottom) } }
                .onChange(of: trace.current?.id) {
                    if nearTail { proxy.scrollTo("trace-tail", anchor: .bottom) }
                }
            }
            usage(trace)
                .padding(.horizontal, RunLayout.panelInset)
                .padding(.top, Space.sm)
                .padding(.bottom, Space.md)
        }
    }

    private func status(_ trace: TurnTrace) -> Text? {
        if trace.running { return Text("In progress").foregroundColor(theme.accent) }
        switch trace.endReason {
        case "completed", nil: return nil
        case "aborted": return Text("Stopped")
        case "max-tokens": return Text("Output limit reached").foregroundColor(DS.warn)
        case "interrupted": return Text("Interrupted").foregroundColor(DS.warn)
        case "blocked": return Text("Run blocked").foregroundColor(DS.warn)
        case "forked": return Text("Forked")
        default: return Text("Request failed: \(trace.endReason ?? "")").foregroundColor(DS.danger)
        }
    }

    private func composition(_ trace: TurnTrace, total: TimeInterval) -> some View {
        let parts: [TraceTimePart] = [
            TraceTimePart(label: "Model", time: trace.modelTime, color: theme.accent),
            TraceTimePart(label: "Tools", time: trace.toolTime, color: DS.traceTool),
            TraceTimePart(label: "Human wait", time: trace.waitTime, color: DS.warn)
        ].filter { ($0.time ?? 0) > 0 }
        let scale = max(0.001, total, parts.reduce(0) { $0 + ($1.time ?? 0) })
        return VStack(alignment: .leading, spacing: Space.sm) {
            if !parts.isEmpty {
                GeometryReader { geometry in
                    let width = max(0, geometry.size.width - 2 * CGFloat(parts.count - 1))
                    HStack(spacing: 2) {
                        ForEach(parts) { part in
                            Rectangle().fill(part.color).frame(width: width * (part.time ?? 0) / scale)
                        }
                        Spacer(minLength: 0)
                    }
                    .background { Rectangle().fill(DS.capsuleTrack) }
                    .clipShape(Capsule())
                }
                .frame(height: RunLayout.usageBarHeight)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Space.lg) { ForEach(parts) { legend($0) } }
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: Space.xs) { ForEach(parts) { legend($0) } }
                }
            }
        }
        .padding(.horizontal, RunLayout.panelInset)
        .padding(.bottom, Space.sm)
    }

    private func legend(_ part: TraceTimePart) -> some View {
        HStack(spacing: Space.xs) {
            Circle().fill(part.color).frame(width: 8, height: 8)
            Text(part.label).type(.bodySmall).foregroundStyle(DS.inkMuted)
            Text(verbatim: RunFormat.duration(part.time)).type(.bodySmall).monospacedDigit().foregroundStyle(DS.inkMuted)
        }
    }

    private func tile(_ span: TraceSpan, trace: TurnTrace, total: TimeInterval, now: Date) -> some View {
        let info = TraceSpanLabel(span, theme: theme)
        let end = span.end ?? now
        let elapsed = max(0, end.timeIntervalSince(span.start))
        return Button { openStep(TraceStep(span)) } label: {
            HStack(alignment: .top, spacing: Space.sm) {
                IconTile(glyph: info.glyph, tint: info.ink, fill: info.fill)
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(spacing: Space.xs) {
                        Text(info.title).type(.bodyMedium).foregroundStyle(span.waiting ? DS.warn : DS.ink)
                            .fixedSize(horizontal: true, vertical: false)
                        if !info.detail.isEmpty {
                            Text(info.detail).font(info.code ? Mono.font(12) : .system(size: 12))
                                .foregroundStyle(DS.inkFaint).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if span.failed { Glyph(glyph: AppIcon.error, size: 14).foregroundStyle(DS.danger) }
                        Text(verbatim: span.open ? RunFormat.clock(elapsed) : RunFormat.duration(span.duration))
                            .type(.bodySmall).monospacedDigit().foregroundStyle(span.waiting ? DS.warn : DS.inkMuted)
                            .fixedSize()
                    }
                    TraceWaterfall(start: trace.start, total: total, spans: [span], now: now)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, span.waiting ? Space.sm : 0)
            .padding(.vertical, Space.md)
            .background {
                if span.waiting { RoundedRectangle(cornerRadius: Radius.md).fill(DS.warnContainer.opacity(0.42)) }
            }
            .padding(.horizontal, span.waiting ? RunLayout.panelInset - Space.sm : RunLayout.panelInset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func group(_ entry: TrajectoryEntry, trace: TurnTrace, total: TimeInterval, now: Date) -> some View {
        let isOpen = expanded.contains(entry.id)
        let summary = ToolSummary(entry.spans)
        let start = entry.spans.first?.start
        let end = entry.spans.compactMap(\.end).max()
        let duration = start.flatMap { start in end.map { $0.timeIntervalSince(start) } }
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if !expanded.insert(entry.id).inserted { expanded.remove(entry.id) }
            } label: {
                HStack(alignment: .top, spacing: Space.sm) {
                    IconTile(glyph: .stack)
                    VStack(spacing: Space.sm) {
                        HStack(spacing: Space.xs) {
                            Text(summary.runLabel()).type(.bodyMedium).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(RunFormat.duration(duration)).type(.bodySmall).monospacedDigit()
                            Glyph(glyph: isOpen ? AppIcon.collapse : AppIcon.expand, size: 16)
                        }
                        TraceWaterfall(start: trace.start, total: total, spans: entry.spans, now: now)
                    }
                }
                .foregroundStyle(DS.inkMuted)
                .padding(.horizontal, RunLayout.panelInset)
                .padding(.vertical, Space.md).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(isOpen ? "Expanded" : "Collapsed"))
            .sensoryFeedback(.selection, trigger: isOpen)
            ExpandReveal(open: isOpen) {
                VStack(spacing: 0) {
                    ForEach(entry.spans) { span in tile(span, trace: trace, total: total, now: now) }
                }
                .padding(.leading, Space.sm)
            }
        }
    }

    private func usage(_ trace: TurnTrace) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .top, spacing: Space.xs) {
                RunPanelStat(label: "Input", value: RunPanelValue.tokens(trace.usage.input), size: 16)
                RunPanelStat(label: "Cache hit", value: RunPanelValue.percent(trace.usage.cacheHitRate), size: 16)
                RunPanelStat(label: "Output", value: RunPanelValue.tokens(trace.usage.output), size: 16)
                RunPanelStat(label: "First token", value: RunFormat.duration(trace.ttft), size: 16)
            }
            let cost = RunPricing.estimate(trace).map(RunFormat.cost)
            let reasoning = trace.usage.reasoning.map { String(localized: "Reasoning: \(RunFormat.tokens($0))") }
            Text([cost, reasoning, String(localized: "Input includes cache hits")].compactMap { $0 }.joined(separator: " · "))
                .type(.bodySmall).foregroundStyle(DS.inkFaint)
        }
        .padding(Space.md)
        .glass(.card, radius: Radius.md)
    }
}

private struct TraceTimePart: Identifiable {
    let label: LocalizedStringKey
    let time: TimeInterval?
    let color: Color
    var id: Color { color }
}

struct TraceStep: Hashable, Identifiable {
    enum Target: Hashable { case model(Int), call(String), event(Int) }
    let target: Target
    var id: Target { target }

    init(_ span: TraceSpan) {
        if span.kind == .model { target = .model(span.step) }
        else if let id = span.callId { target = .call(id) }
        else { target = .event(span.seq) }
    }

    func spans(in trace: TurnTrace) -> [TraceSpan] {
        switch target {
        case .model(let step): trace.spans.filter { $0.kind == .model && $0.step == step }
        case .call(let id): trace.spans.filter { $0.callId == id }
        case .event(let seq): trace.spans.filter { $0.seq == seq }
        }
    }
}

private struct TrajectoryEntry: Identifiable {
    let id: TraceSpan.ID
    let spans: [TraceSpan]

    static func group(_ spans: [TraceSpan]) -> [TrajectoryEntry] {
        var result: [TrajectoryEntry] = []
        var batch: [TraceSpan] = []
        func flush() {
            if batch.count >= 3, let first = batch.first {
                result.append(TrajectoryEntry(id: first.id, spans: batch))
            } else {
                result += batch.map { TrajectoryEntry(id: $0.id, spans: [$0]) }
            }
            batch.removeAll(keepingCapacity: true)
        }
        for span in spans {
            let groupable = span.kind == .tool && !span.open
            if !groupable || batch.first.map({ $0.step != span.step }) == true { flush() }
            if groupable { batch.append(span) }
            else { result.append(TrajectoryEntry(id: span.id, spans: [span])) }
        }
        flush()
        return result
    }
}
