// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
public struct TextChange: Sendable, Equatable {
    public let before: String?
    public let after: String
    public init(before: String?, after: String) { self.before = before; self.after = after }
    /// The coordinates are within the tool excerpt, not the whole file.
    public var lines: [String] {
        let new = after.isEmpty ? [] : after.components(separatedBy: "\n")
        guard let before else { return new.map { "+" + $0 } }
        let old = before.isEmpty ? [] : before.components(separatedBy: "\n")
        let cells = old.count.multipliedReportingOverflow(by: new.count)
        guard !cells.overflow, cells.partialValue <= 400 * 400 else {
            return old.map { "-" + $0 } + new.map { "+" + $0 }
        }
        let difference = new.difference(from: old)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change { case .remove(let index, _, _): removed.insert(index); case .insert(let index, _, _): inserted.insert(index) }
        }
        var output: [String] = [], a = 0, b = 0
        while a < old.count || b < new.count {
            if a < old.count && removed.contains(a) { output.append("-" + old[a]); a += 1 }
            else if b < new.count && inserted.contains(b) { output.append("+" + new[b]); b += 1 }
            else if a < old.count && b < new.count { output.append(" " + new[b]); a += 1; b += 1 }
            else { break }
        }
        return output
    }
}
struct FileReadWindow: Sendable, Equatable {
    let firstLine: Int
    var lines: [String]
}

public struct ToolPresentation: Sendable, Equatable {
    public let changes: [TextChange]
    public let created: Bool
    let readWindow: FileReadWindow?
    public init(_ value: Any?) {
        let meta = value as? [String: Any] ?? [:]
        created = meta["operation"] as? String == "create"
        readWindow = Self.readWindow(meta["lines"])
        changes = (meta["diffs"] as? [[String: Any]] ?? []).compactMap {
            guard let after = $0["newText"] as? String else { return nil }
            return TextChange(before: $0["oldText"] as? String, after: after)
        }
    }

    private static func readWindow(_ raw: Any?) -> FileReadWindow? {
        guard let rows = raw as? [[String: Any]], let first = tokenCount(rows.first?["number"]), first > 0 else { return nil }
        var lines: [String] = []
        for row in rows {
            guard let number = tokenCount(row["number"]), number - first == lines.count,
                  let text = row["text"] as? String else { break }
            lines.append(text)
        }
        return lines.isEmpty ? nil : FileReadWindow(firstLine: first, lines: lines)
    }
}
