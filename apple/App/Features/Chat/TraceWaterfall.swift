// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/lib/ui/chat/trajectory_sheet.dart (SpanGlyph, TimelineBar).
import DSHClient
import SwiftUI

struct TraceWaterfall: View {
    let start: Date
    let total: TimeInterval
    let spans: [TraceSpan]
    let now: Date
    @Environment(\.designTheme) private var theme

    var body: some View {
        Canvas { context, size in
            let track = CGRect(origin: .zero, size: size)
            context.fill(Path(roundedRect: track, cornerRadius: size.height / 2), with: .color(DS.capsuleTrack))
            let scale = max(total, 0.001)
            for span in spans {
                let end = span.end ?? now
                let elapsed = max(0, end.timeIntervalSince(span.start))
                let fraction = min(1, max(0, span.start.timeIntervalSince(start) / scale))
                let left = min(max(0, size.width - 3), size.width * fraction)
                let width = min(size.width - left, max(3, size.width * min(1, elapsed / scale)))
                guard width > 0 else { continue }
                let rect = CGRect(x: left, y: 0, width: width, height: size.height)
                let color = TraceSpanLabel(span, theme: theme).bar
                var segment = context
                segment.clip(to: Path(roundedRect: rect, cornerRadius: size.height / 2))
                let head = span.ttft.map { width * min(1, $0 / max(elapsed, 0.001)) } ?? 0
                if head > 0 {
                    segment.fill(Path(CGRect(x: left, y: 0, width: head, height: size.height)), with: .color(color.opacity(0.32)))
                }
                let tail = CGRect(x: left + head, y: 0, width: width - head, height: size.height)
                if tail.width > 0 {
                    segment.fill(Path(tail), with: span.open
                        ? .linearGradient(Gradient(colors: [color, color.opacity(0.18)]),
                                          startPoint: CGPoint(x: tail.minX, y: 0), endPoint: CGPoint(x: tail.maxX, y: 0))
                        : .color(color))
                }
            }
        }
        .frame(height: RunLayout.traceBarHeight)
        .accessibilityHidden(true)
    }
}

struct TraceSpanLabel {
    let title: String
    let detail: String
    let code: Bool
    let glyph: DshGlyph
    let ink: Color
    let fill: Color
    let bar: Color

    init(_ span: TraceSpan, theme: DesignTheme) {
        let tool = ToolRow(id: span.callId ?? "", name: span.toolName ?? "", arguments: span.arguments ?? "",
                           result: span.result?.text, failed: span.failed, presentation: span.result?.presentation ?? ToolPresentation(nil))
        let args = tool.args
        let view = ToolPresenterRegistry.present(tool, args: args, theme: theme)
        let toolTitle = String(localized: String.LocalizationValue(view.style.label))
        switch span.kind {
        case .model:
            let replying = span.model?.toolCalls == 0 && span.model?.hasText == true
            if replying {
                title = span.model?.interrupted == true ? String(localized: "Reply interrupted") : String(localized: "Reply")
            } else {
                title = String(localized: "Thinking")
            }
            var notes: [String] = []
            if let retries = span.model?.retries, !retries.isEmpty {
                notes.append(String(localized: "\(retries.count) retries"))
            }
            if let calls = span.model?.toolCalls, calls > 0 {
                notes.append(String(localized: "Chose to call \(calls) tools"))
            }
            detail = notes.joined(separator: " · ")
            code = false
            glyph = replying ? .chats : .lightbulb
            ink = theme.accent
            fill = theme.accentContainer
            bar = theme.accent
        case .approval, .question:
            title = span.kind == .approval
                ? (span.open ? String(localized: "Needs approval") : String(localized: "Waited for approval"))
                : (span.open ? String(localized: "Needs your answer") : String(localized: "Waited for an answer"))
            if span.kind == .approval {
                detail = [toolTitle, view.summary].filter { !$0.isEmpty }.joined(separator: " ")
            } else {
                detail = args["questions"]?.array?.first?["question"]?.string ?? view.summary
            }
            code = false
            glyph = span.kind == .approval ? AppIcon.approval : AppIcon.question
            ink = DS.warn
            fill = DS.warnContainer
            bar = DS.warn
        case .tool:
            title = toolTitle
            detail = view.summary
            code = [.command, .read, .edit, .search, .web].contains(tool.family)
            glyph = view.style.glyph
            ink = view.style.tint
            fill = view.style.fill
            switch tool.family {
            case .read: bar = DS.traceRead
            case .web: bar = DS.traceWeb
            case .agent: bar = DS.traceAgent
            case .edit: bar = DS.traceEdit
            case .search: bar = DS.traceSearch
            case .todo: bar = DS.traceTodo
            default: bar = DS.traceTool
            }
        }
    }
}
