// SPDX-License-Identifier: AGPL-3.0-or-later
// Tool categorization, summaries and numbered diff hunks from
// DSH Go app/lib/ui/chat/{turn_summary,tool_view}.dart.
import Foundation

public enum ToolFamily: Sendable {
    case command, edit, read, search, web, agent, todo, other

    public init(name: String, operation: String? = nil) {
        switch name {
        case "bash", "pwsh": self = .command
        case "write", "edit": self = .edit
        case "str_replace_editor": self = operation == "view" ? .read : .edit
        case "read", "read_image": self = .read
        case "grep", "glob": self = .search
        case "web_fetch", "web_search": self = .web
        case "subagent", "subagent_fork", "send_message", "interrupt_agent", "workflow", "ralph": self = .agent
        case "todo_write": self = .todo
        default: self = .other
        }
    }
}

public struct ToolSummary: Equatable, Sendable {
    public private(set) var commands = 0
    public private(set) var editedFiles = 0
    public private(set) var readFiles = 0
    public private(set) var searches = 0
    public private(set) var web = 0
    public private(set) var agents = 0
    public private(set) var todos = 0
    public private(set) var other = 0
    public private(set) var failed = 0
    public private(set) var total = 0

    public init(_ spans: [TraceSpan]) {
        var edited: Set<String> = [], read: Set<String> = []
        for span in spans where span.kind == .tool || span.kind == .question {
            let tool = ChangeTool(span)
            guard !tool.sandboxBlocked, !span.cutShort, span.outcome?.blocksTool != true else { continue }
            if span.failed { failed += 1; continue }
            total += 1
            let path = tool.path.map(TurnFileChange.normalized) ?? "#\(span.seq)"
            switch tool.family {
            case .command: commands += 1
            case .edit: edited.insert(path)
            case .read: read.insert(path)
            case .search: searches += 1
            case .web: web += 1
            case .agent: agents += 1
            case .todo: todos += 1
            case .other: other += 1
            }
        }
        editedFiles = edited.count
        readFiles = read.count
    }
}

public struct DiffHunk: Equatable, Sendable {
    public let lines: [String]
    public let edit: Int
    public var oldStart: Int?
    public var newStart: Int?
    public var oldCount: Int { lines.filter { !$0.hasPrefix("+") }.count }
    public var newCount: Int { lines.filter { !$0.hasPrefix("-") }.count }
}

public struct TurnFileChange: Identifiable, Equatable, Sendable {
    public var id: String { shownPath }
    public let path: String
    public let created: Bool
    public private(set) var edits = 0
    public private(set) var hunks: [DiffHunk] = []
    public private(set) var added = 0
    public private(set) var removed = 0
    public private(set) var lastCallId: String?
    public var shownPath: String { Self.normalized(path) }
    public var fileName: String { String(shownPath.split(separator: "/").last ?? Substring(shownPath)) }
    public var directory: String {
        guard let slash = shownPath.lastIndex(of: "/") else { return "" }
        return String(shownPath[..<slash])
    }

    public var patch: String {
        var lines = [created ? "--- /dev/null" : "--- a/\(shownPath)", "+++ b/\(shownPath)"]
        for hunk in hunks {
            let old = hunk.oldCount == 0 ? 0 : (hunk.oldStart ?? 1)
            let new = hunk.newCount == 0 ? 0 : (hunk.newStart ?? 1)
            lines.append("@@ -\(old),\(hunk.oldCount) +\(new),\(hunk.newCount) @@")
            lines += hunk.lines
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func normalized(_ path: String) -> String {
        var path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while path.hasPrefix("./") { path.removeFirst(2) }
        let workspace = "/root/workspace"
        if path.hasPrefix(workspace + "/") { return String(path.dropFirst(workspace.count + 1)) }
        return path == workspace ? "." : path
    }

    static func collect(_ spans: [TraceSpan]) -> [TurnFileChange] {
        var files: [TurnFileChange] = []
        var indexes: [String: Int] = [:]
        var known: [String: FileReadWindow] = [:]
        // Use durable result order, since parallel calls can finish out of order.
        let results = spans.filter { $0.kind == .tool && !$0.failed && $0.result != nil }
            .sorted { ($0.result?.seq ?? 0) < ($1.result?.seq ?? 0) }
        for span in results {
            let tool = ChangeTool(span)
            if tool.family == .command {
                known.removeAll()
                continue
            }
            guard let rawPath = tool.path, !normalized(rawPath).isEmpty else { continue }
            let path = normalized(rawPath)
            if tool.family == .read {
                if let window = tool.readWindow { known[path] = window }
                continue
            }
            guard tool.family == .edit else { continue }
            let index = indexes[path] ?? files.count
            let hunks = tool.hunks(edit: index < files.count ? files[index].edits + 1 : 1, known: &known[path])
            guard let hunks else { continue }
            if index == files.count {
                files.append(TurnFileChange(path: rawPath, created: tool.created))
                indexes[path] = index
            }
            files[index].edits += 1
            files[index].lastCallId = span.callId
            files[index].hunks += hunks
            for line in hunks.flatMap(\.lines) {
                if line.hasPrefix("+") { files[index].added += 1 }
                if line.hasPrefix("-") { files[index].removed += 1 }
            }
        }
        return files
    }
}

private struct ChangeTool {
    let span: TraceSpan
    let args: [String: JSONValue]
    let family: ToolFamily

    init(_ span: TraceSpan) {
        self.span = span
        args = (try? JSONValue(data: Data((span.arguments ?? "").utf8)).object) ?? [:]
        family = ToolFamily(name: span.toolName ?? "", operation: args["command"]?.string)
    }

    var path: String? { args["file_path"]?.string ?? args["path"]?.string }
    var operation: String? { span.toolName == "str_replace_editor" ? args["command"]?.string : nil }
    var created: Bool { operation == "create" || (span.toolName == "write" && span.result?.presentation.created == true) }
    var writtenContent: String? {
        if span.toolName == "write" { return args["content"]?.string }
        return operation == "create" ? args["file_text"]?.string : nil
    }
    var sandboxBlocked: Bool {
        guard family == .command, span.failed, let result = span.result else { return false }
        let marker = "no sandbox backend is usable"
        return result.text.contains(marker) || result.failureReason?.contains(marker) == true
    }

    var readWindow: FileReadWindow? {
        guard let result = span.result else { return nil }
        if let window = result.presentation.readWindow { return window }
        var first: Int?
        var lines: [String] = []
        for line in result.text.components(separatedBy: "\n") {
            guard let colon = line.firstIndex(of: ":"), let number = Int(line[..<colon]), number > 0 else {
                if first != nil { break }
                continue
            }
            if let first, number - first != lines.count { break }
            if first == nil { first = number }
            let text = line[line.index(after: colon)...]
            lines.append(String(text.hasPrefix(" ") ? text.dropFirst() : text))
        }
        return first.map { FileReadWindow(firstLine: $0, lines: lines) }
    }

    var blocks: [TextChange] {
        if let changes = span.result?.presentation.changes, !changes.isEmpty { return changes }
        let old = span.toolName == "edit" ? "old_string" : "old_str"
        let new = span.toolName == "edit" ? "new_string" : "new_str"
        if span.toolName == "edit" || operation == "str_replace", let before = args[old]?.string, let after = args[new]?.string {
            return [TextChange(before: before, after: after)]
        }
        return []
    }

    func hunks(edit: Int, known: inout FileReadWindow?) -> [DiffHunk]? {
        let content = writtenContent
        let blocks = self.blocks
        if !created, !blocks.isEmpty {
            let hunks = place(blocks, edit: edit, known: &known, written: content)
            if let content { known = FileReadWindow(firstLine: 1, lines: contentLines(content)) }
            return hunks
        }
        if operation == "insert", let text = args["new_str"]?.string {
            let after = args["insert_line"]?.int.flatMap { (0..<Int.max).contains($0) ? $0 : nil }
            if let after, let first = known?.firstLine, after - first + 1 >= 0, after - first + 1 <= (known?.lines.count ?? 0) {
                known?.lines.insert(contentsOf: contentLines(text), at: after - first + 1)
            } else { known = nil }
            return [DiffHunk(lines: addedLines(text), edit: edit, newStart: after.map { $0 + 1 })]
        }
        guard let content else {
            known = nil
            return nil
        }
        known = FileReadWindow(firstLine: 1, lines: contentLines(content))
        return [DiffHunk(lines: addedLines(content), edit: edit, newStart: created ? 1 : nil)]
    }

    private func place(_ blocks: [TextChange], edit: Int, known: inout FileReadWindow?, written: String?) -> [DiffHunk] {
        var delta = 0
        var hunks: [DiffHunk] = []
        for block in blocks {
            var hunk = DiffHunk(lines: block.lines, edit: edit)
            let old = block.before.map { $0.components(separatedBy: "\n") } ?? []
            let new = block.after.components(separatedBy: "\n")
            if var window = known, let at = window.uniqueIndex(of: old) {
                let newStart = window.firstLine + at
                hunk.oldStart = newStart - delta
                hunk.newStart = newStart
                window.lines.replaceSubrange(at..<(at + old.count), with: new)
                delta += new.count - old.count
                known = window
            } else { known = nil }
            hunks.append(hunk)
        }
        guard known == nil, let written else { return hunks }
        // A whole-file write supplies the new text. Place each block in
        // order, then recover the old coordinates from the preceding edits.
        let window = FileReadWindow(firstLine: 1, lines: contentLines(written))
        var placed = hunks
        var from = 0
        delta = 0
        for (index, block) in blocks.enumerated() {
            let new = block.after.components(separatedBy: "\n")
            guard let at = window.uniqueIndex(of: new, from: from) else { return hunks }
            placed[index].newStart = at + 1
            placed[index].oldStart = at + 1 - delta
            from = at + new.count
            delta += new.count - (block.before?.components(separatedBy: "\n").count ?? 0)
        }
        return placed
    }

    private func addedLines(_ text: String) -> [String] { contentLines(text).map { "+" + $0 } }
    private func contentLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        return (text.hasSuffix("\n") ? String(text.dropLast()) : text).components(separatedBy: "\n")
    }
}

private extension FileReadWindow {
    func uniqueIndex(of needle: [String], from: Int = 0) -> Int? {
        guard !needle.isEmpty, from <= lines.count - needle.count else { return nil }
        var found: Int?
        for i in from...(lines.count - needle.count) where lines[i..<(i + needle.count)].elementsEqual(needle) {
            if found != nil { return nil }
            found = i
        }
        return found
    }
}
