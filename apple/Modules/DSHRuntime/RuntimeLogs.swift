// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

// Accessed exclusively on RuntimeEngine.worker; never writes engine output to disk.
public final class RuntimeLogs {
    private var sequence: Int64 = 0
    private var entries: [[String: Any]] = []
    private var pending: [[String: Any]] = []

    public static func redact(_ text: String) -> String {
        var value = text
        // Android's CrashClassifier.redact token rule, plus credential boundaries.
        let rules = [
            (#"token=[A-Za-z0-9._~%\-]+"#, "token=•••"),
            (#"(?i)(authorization|cookie|set-cookie)\s*:\s*.*"#, "$1: •••"),
            (#"(?i)(authorization\s*=\s*(?:bearer\s+)?|bearer\s+)[^\s,;]+"#, "$1•••"),
            (#"(?i)((?:api[_-]?key|token|password|secret|cookie)\s*[\"']?\s*[:=]\s*[\"']?)[^\s\"',;}]+"#, "$1•••"),
            (#"sk-[A-Za-z0-9_-]+"#, "•••"),
        ]
        for (pattern, replacement) in rules {
            value = value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return String(value.prefix(16384))
    }
    func append(_ line: String, stream: String) {
        sequence += 1
        let entry: [String: Any] = ["seq": sequence, "line": Self.redact(line), "stream": stream]
        entries.append(entry); pending.append(entry)
        if entries.count > 2000 { entries.removeFirst(entries.count - 2000) }
        if pending.count > 2000 { pending.removeFirst(pending.count - 2000) }
    }
    func snapshot(lines: Int) -> [String: Any] {
        ["entries": Array(entries.suffix(max(0, min(lines, 2000)))), "throughSeq": sequence]
    }
    func tail(lines: Int) -> [String] {
        entries.suffix(max(0, min(lines, 2000))).compactMap { $0["line"] as? String }
    }
    func drain() -> [[String: Any]] {
        let batch = pending; pending.removeAll(keepingCapacity: true); return batch
    }
}
