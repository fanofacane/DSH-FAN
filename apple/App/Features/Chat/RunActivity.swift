// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/lib/ui/chat/run_info.dart (runActivityOf and toolVerb).
import DSHClient
import SwiftUI

struct RunActivity: Equatable {
    enum Kind { case stopping, question, approval, tool, writing, thinking, retry, waiting, compaction }

    let kind: Kind
    let title: String
    var detail = ""
    var code = false
    var since: Date?
    var turnStart: Date?
    var narration: String?
    var lastTool: TraceSpan?
    var toolsDone = 0
    var firstStep = false
    var rateLimited = false
    var waitingForPerson: Bool { kind == .approval || kind == .question }

    @MainActor static func resolve(_ chat: AppSession, theme: DesignTheme) -> RunActivity? {
        let transcript = chat.transcript
        let trace = transcript.traceFold.running
        let spans = trace?.spans ?? []
        let open = spans.filter(\.open)
        let model = open.last { $0.kind == .model }
        let start = trace?.start

        if transcript.stopping {
            return RunActivity(kind: .stopping, title: String(localized: "Stopping"), turnStart: start)
        }
        if transcript.turnRunning {
            if let question = chat.requests.currentQuestion?.questions.first {
                return RunActivity(kind: .question, title: String(localized: "Needs your answer"),
                                   detail: question.question.split(whereSeparator: \.isWhitespace).joined(separator: " "),
                                   since: open.last { $0.kind == .question }?.start, turnStart: start)
            }
            let approval = chat.requests.currentApproval
            let wait = open.last { $0.kind == .approval && (approval?.callId == nil || $0.callId == approval?.callId) }
            if approval != nil || wait != nil {
                let tool = ToolRow(id: wait?.callId ?? "", name: approval?.toolName ?? wait?.toolName ?? "",
                                   arguments: wait?.arguments ?? "")
                let description = describe(tool, theme: theme)
                return RunActivity(kind: .approval, title: String(localized: "Needs approval"),
                                   detail: [description.verb, description.summary].filter { !$0.isEmpty }.joined(separator: " "),
                                   since: wait?.start, turnStart: start)
            }
        }
        if let since = transcript.traceFold.compactionStart {
            return RunActivity(kind: .compaction, title: String(localized: "Compacting context"), since: since, turnStart: start ?? since)
        }
        guard transcript.busy else { return nil }
        let tools = open.filter { $0.kind == .tool }
        if let tool = tools.last {
            let row = ToolRow(id: tool.callId ?? "", name: tool.toolName ?? "", arguments: tool.arguments ?? "")
            let description = describe(row, theme: theme)
            let extra = tools.count > 1 ? String(localized: "\(tools.count) running") : ""
            return RunActivity(kind: .tool, title: description.verb, detail: [description.summary, extra].filter { !$0.isEmpty }.joined(separator: "  "),
                               code: description.code, since: tool.start, turnStart: start)
        }
        if let tool = transcript.draft?.tools.last {
            let description = describe(tool, theme: theme)
            return RunActivity(kind: .tool, title: description.verb, detail: description.summary, code: description.code,
                               since: model?.start, turnStart: start)
        }
        let draft = transcript.draft
        let kind: Kind
        let title: String
        if draft?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            kind = .writing
            title = String(localized: "Writing reply")
        } else if draft?.reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            kind = .thinking
            title = String(localized: "Thinking now")
        } else if let retry = transcript.retrying {
            return RunActivity(kind: .retry, title: String(localized: "Retrying"), detail: String(localized: "Attempt \(retry.retry)"),
                               since: model?.start, turnStart: start, rateLimited: retry.code == "RATE_LIMIT")
        } else {
            kind = .waiting
            title = String(localized: "Thinking now")
        }
        let latestText = transcript.items.reversed().prefix { $0.role != .user }
            .first { $0.role == .assistant && !$0.text.isEmpty }?.text
        let last = spans.filter { !$0.open && $0.kind != .approval }.max { ($0.end ?? $0.start) < ($1.end ?? $1.start) }
        return RunActivity(kind: kind, title: title, since: model?.start ?? start, turnStart: start,
                           narration: latestText.flatMap(ActivityCopy.narration),
                           lastTool: last?.kind == .tool ? last : nil,
                           toolsDone: spans.filter { !$0.open && $0.kind == .tool }.count,
                           firstStep: (trace?.steps ?? 0) == 0)
    }

    private static func describe(_ tool: ToolRow, theme: DesignTheme) -> (verb: String, summary: String, code: Bool) {
        let args = tool.args
        let shown = ToolPresenterRegistry.present(tool, args: args, theme: theme)
        let verb: String.LocalizationValue
        switch tool.family {
        case .command: verb = "Running tool"
        case .edit: verb = tool.name == "write" || args["command"]?.string == "create" ? "Writing file" : "Editing file"
        case .read: verb = tool.name == "read_image" ? "View image" : "Reading file"
        case .search: verb = tool.name == "glob" ? "Find" : "Searching files"
        case .web: verb = tool.name == "web_search" ? "Search web" : "View web"
        case .agent where tool.name == "subagent": verb = "Send subagent"
        case .todo: verb = "Update to-dos"
        default: return (String(localized: String.LocalizationValue(shown.style.label)), shown.summary, false)
        }
        let code = [ToolFamily.command, .edit, .read, .search, .web].contains(tool.family)
        return (String(localized: verb), shown.summary, code)
    }
}
