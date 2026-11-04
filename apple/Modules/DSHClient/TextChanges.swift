// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
public struct TextChange: Sendable, Equatable {
    public let before: String?
    public let after: String
    public init(before: String?, after: String) { self.before = before; self.after = after }
    /// The coordinates are within the tool excerpt, not the whole file.
    public var lines: [String] {
        let new = after.components(separatedBy: "\n")
        guard let before else { return new.map { "+" + $0 } }
        let old = before.components(separatedBy: "\n")
        guard old.count <= 2000, new.count <= 2000 else { return ["-" + before, "+" + after] }
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
public struct ToolPresentation: Sendable, Equatable {
    public let changes: [TextChange]
    public let created: Bool
    public init(_ value: Any?) {
        let meta = value as? [String: Any] ?? [:]
        created = meta["operation"] as? String == "create"
        changes = (meta["diffs"] as? [[String: Any]] ?? []).compactMap {
            guard let after = $0["newText"] as? String else { return nil }
            return TextChange(before: $0["oldText"] as? String, after: after)
        }
    }
}
