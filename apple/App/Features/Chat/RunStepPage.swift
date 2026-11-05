// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/lib/ui/chat/step_detail_page.dart.
import DSHClient
import SwiftUI

struct RunStepPage: View {
    let step: TraceStep
    let trace: TurnTrace?
    let items: [ChatItem]
    var skew: TimeInterval = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.designTheme) private var theme
    @State private var diff: TurnFileChange?
    @State private var wrapsDiff = true

    private var spans: [TraceSpan] { trace.map(step.spans) ?? [] }
    private var span: TraceSpan? { spans.last { $0.kind != .approval } ?? spans.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Space.md) {
                    if let trace, let span {
                        LiveRunClock(since: span.open ? span.start : nil, skew: skew) { now in
                            if span.kind == .model { modelFacts(span, trace: trace, now: now) }
                            else { toolFacts(span, trace: trace, now: now) }
                        }
                        if span.kind == .model { modelContent(span, trace: trace) }
                        else { toolContent(span, trace: trace) }
                    } else {
                        Text("This step isn’t in the loaded records")
                            .type(.bodyMedium).foregroundStyle(DS.inkFaint)
                    }
                }
                .frame(maxWidth: Space.readingWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.xxl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { AppBackdrop() }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $diff) { file in TurnDiffPage(files: [file], initialIndex: 0, wraps: $wrapsDiff) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            GlassIconButton(glyph: AppIcon.back, label: "Back", size: 44) { dismiss() }
                .padding(.horizontal, Space.md)
                .frame(minHeight: RunLayout.pageBarHeight)
            VStack(alignment: .leading, spacing: Space.xs) {
                if let span {
                    let label = TraceSpanLabel(span, theme: theme)
                    Text(verbatim: label.title).type(.pageTitle)
                    if span.kind == .model {
                        let text = span.open ? String(localized: "Model is processing") : String(localized: "Model request")
                        Text([text, label.detail].filter { !$0.isEmpty }.joined(separator: " · "))
                            .type(.bodyMedium).foregroundStyle(DS.inkMuted)
                    } else if !label.detail.isEmpty {
                        HStack(spacing: Space.sm) {
                            Glyph(glyph: label.glyph, size: 16).foregroundStyle(label.ink)
                            Text(verbatim: label.detail).font(label.code ? Mono.font(13) : .system(size: 13))
                                .foregroundStyle(DS.inkMuted).lineLimit(2)
                        }
                    }
                } else {
                    Text("Step details").type(.pageTitle)
                }
            }
            .foregroundStyle(DS.ink)
            .padding(.horizontal, Space.xxl)
        }
        .padding(.bottom, Space.xl)
    }

    private func modelFacts(_ span: TraceSpan, trace: TurnTrace, now: Date) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            RunPanelSection(title: "Step timing") {
                StepFact(title: "Started", value: time(span.start))
                StepFact(title: "Duration", value: elapsed(span, now: now))
                StepFact(title: "First token", value: RunFormat.duration(span.ttft))
                StepFact(title: "Generation time", value: span.open ? RunPanelValue.unreported : RunFormat.duration(span.decoding))
                if let speed = span.tokensPerSecond {
                    let number = speed.formatted(.number.precision(.fractionLength(speed < 10 ? 1 : 0)))
                    StepFact(title: "Speed", value: String(localized: "\(number) tokens/s"))
                }
                if let retry = span.model?.retries, !retry.isEmpty {
                    StepFact(title: "Retry", value: ([String(localized: "\(retry.count) retries")] + retry.prefix(2)).joined(separator: " · "))
                }
                StepFact(title: "Model", value: span.model?.model ?? RunPanelValue.unreported, mono: true)
                StepFact(title: "Position", value: position(span, in: trace))
            }
            let usage = span.model?.usage
            RunPanelSection(title: "Usage") {
                StepFact(title: "Input", value: RunPanelValue.tokens(usage?.input))
                StepFact(title: "Cached input", value: RunPanelValue.tokens(usage?.cacheRead))
                StepFact(title: "Cache miss", value: RunPanelValue.tokens(usage?.uncachedInput))
                if let writes = usage?.cacheWrite, writes > 0 { StepFact(title: "Cache writes", value: RunPanelValue.tokens(writes)) }
                StepFact(title: "Output", value: RunPanelValue.tokens(usage?.output))
                if let reasoning = usage?.reasoning {
                    StepFact(title: "Reasoning", value: RunPanelValue.tokens(reasoning))
                    if let output = usage?.output, output >= reasoning {
                        StepFact(title: "Answer", value: RunPanelValue.tokens(output - reasoning))
                    }
                }
            }
        }
    }

    @ViewBuilder private func modelContent(_ span: TraceSpan, trace: TurnTrace) -> some View {
        let reply = span.open ? items.last { $0.state == .streaming } : items.first { $0.seq == span.seq }
        if let reply, !reply.reasoning.isEmpty { StepContentSection(title: "Reasoning trace", text: reply.reasoning, code: false) }
        if let reply, !reply.text.isEmpty {
            StepContentSection(title: (span.model?.toolCalls ?? 0) > 0 ? "Explanation" : "Reply", text: reply.text, code: false)
        }
        let tools = trace.spans.filter { $0.step == span.step && ($0.kind == .tool || $0.kind == .question) }
        if !tools.isEmpty {
            RunPanelSection(title: "Tools in this step") {
                ForEach(tools) { tool in
                    let label = TraceSpanLabel(tool, theme: theme)
                    NavigationLink(value: TraceStep(tool)) {
                        HStack(spacing: Space.sm) {
                            IconTile(glyph: label.glyph, tint: label.ink, fill: label.fill)
                            Text(label.title).type(.bodyMedium).foregroundStyle(DS.ink)
                            Text(label.detail).type(.bodySmall).foregroundStyle(DS.inkMuted).lineLimit(1)
                            Spacer(minLength: 0)
                            Glyph(glyph: AppIcon.disclosure, size: 16).foregroundStyle(DS.inkFaint)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func toolFacts(_ span: TraceSpan, trace: TurnTrace, now: Date) -> some View {
        let wait = spans.last { $0.kind == .approval }
        let work = spans.last { $0.kind != .approval }
        return RunPanelSection {
            StepFact(title: "Tool", value: span.toolName ?? RunPanelValue.unreported, mono: true)
            StepFact(title: "Status", value: status(span),
                     color: span.failed ? DS.danger : span.open ? theme.accent : span.result?.failed == false ? DS.success : DS.ink)
            StepFact(title: "Dispatched", value: time(span.dispatched ?? span.start))
            if let wait {
                let suffix = wait.outcome.map { approval($0) }
                let duration = [elapsed(wait, now: now), suffix].compactMap { $0 }.joined(separator: " · ")
                StepFact(title: "Approval wait", value: duration, color: DS.warn)
            }
            if let work {
                StepFact(title: work.kind == .question ? "Waited for an answer" : "Execution", value: elapsed(work, now: now))
            }
            StepFact(title: "Position", value: position(span, in: trace))
        }
    }

    @ViewBuilder private func toolContent(_ span: TraceSpan, trace: TurnTrace) -> some View {
        if let arguments = span.arguments, !arguments.isEmpty, arguments != "{}" {
            let parsed = try? JSONValue(data: Data(arguments.utf8))
            let encoder = JSONEncoder()
            let pretty = parsed.flatMap { value -> String? in
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) }
            }
            StepContentSection(title: "Arguments", text: pretty ?? arguments)
        }
        if let result = span.result {
            if !result.presentation.changes.isEmpty, !span.failed {
                let text = result.presentation.changes.flatMap(\.lines).joined(separator: "\n")
                let file = trace.changes.first { $0.lastCallId == span.callId }
                StepContentSection(title: "Changes", text: text, viewDiff: file.map { file in { diff = file } })
            }
            let text = result.text.isEmpty ? result.failureCode ?? String(localized: "No output") : result.text
            let title: LocalizedStringKey = result.failed ? "Error" :
                (span.toolName == "bash" || span.toolName == "pwsh" ? "Output" : "Result")
            StepContentSection(title: title, text: text)
        } else if !span.open {
            StepContentSection(title: "Result", text: RunPanelValue.unreported, code: false)
        }
    }

    private func position(_ span: TraceSpan, in trace: TurnTrace) -> String {
        String(localized: "Turn \(trace.turn) · Step \(span.step)")
    }

    private func elapsed(_ span: TraceSpan, now: Date) -> String {
        if span.open { return RunFormat.clock(now.timeIntervalSince(span.start)) }
        return RunFormat.duration(span.duration)
    }

    private func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().second())
    }

    private func approval(_ outcome: TraceApproval) -> String {
        switch outcome {
        case .allowedOnce: String(localized: "Allowed once")
        case .rejected: String(localized: "Declined")
        case .cancelled: String(localized: "Cancelled")
        case .unavailable: String(localized: "Unavailable")
        case .unknown: RunPanelValue.unreported
        }
    }

    private func status(_ span: TraceSpan) -> String {
        if span.kind == .approval {
            return span.outcome.map(approval) ?? String(localized: "Needs approval")
        }
        if span.outcome == .rejected { return String(localized: "Declined") }
        if span.cutShort || span.outcome == .cancelled { return String(localized: "Cancelled") }
        if span.failed { return String(localized: "Failed") }
        if span.open { return String(localized: "In progress") }
        return String(localized: "Succeeded")
    }
}

private struct StepFact: View {
    let title: LocalizedStringKey
    let value: String
    var mono = false
    var color: Color = DS.ink

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Text(title).type(.bodyMedium).foregroundStyle(DS.inkMuted)
                .frame(width: 80, alignment: .leading)
            Text(verbatim: value)
                .font(mono ? Mono.font(13) : .system(size: 14).monospacedDigit())
                .foregroundStyle(color)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .frame(minHeight: RunLayout.stepFactHeight, alignment: .leading)
    }
}

private struct StepContentSection: View {
    let title: LocalizedStringKey
    let text: String
    var code = true
    var viewDiff: (() -> Void)?
    @State private var copies = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).type(.labelMedium).foregroundStyle(DS.inkMuted)
                Spacer()
                if let viewDiff { Button("Full screen", action: viewDiff).type(.labelMedium) }
                Button {
                    UIPasteboard.general.string = text
                    copies += 1
                } label: { Glyph(glyph: copies > 0 ? AppIcon.done : AppIcon.copy, size: 16).frame(width: 36, height: 36) }
                .accessibilityLabel(Text("Copy"))
                .sensoryFeedback(.impact(weight: .light), trigger: copies)
            }
            .padding(.leading, Space.md)
            .background { Rectangle().fill(code ? DS.codeWellHeader : Color.clear) }
            Text(verbatim: text.count > 60_000 ? String(text.prefix(60_000)) + "\n…" : text)
                .font(code ? Mono.font(12.5) : .system(size: 14))
                .foregroundStyle(DS.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.md)
        }
        .background { RoundedRectangle(cornerRadius: Radius.md).fill(code ? DS.codeWell : DS.surfaceLow) }
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}
