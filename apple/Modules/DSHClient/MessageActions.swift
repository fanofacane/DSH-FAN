// SPDX-License-Identifier: AGPL-3.0-or-later
// Forking a session at an exact event (port of forkAt / forkPointAfterReply /
// forkPointBeforePrompt in 原 Flutter 版 dsh_client/lib/src/messages_api.dart).
// DSH logs are append-only, so retry, branch and edit all fork a new chat.
import Foundation

public struct ForkOutcome: Sendable {
    public let sessionId: String
    public let title: String?
}

extension DSHClient {
    /// `session/fork` at `atSeq`, then drops prompts the fork inherited from the
    /// inbox and renames an inherited title `T` to `T (1)`.
    public func forkAt(_ sessionId: String, atSeq: Int, sourceTitle: String?) async throws -> ForkOutcome {
        let value = try await rpc("session/fork", ["request": ["sessionId": sessionId, "atSeq": atSeq]]) as? [String: Any]
        guard let child = value?["sessionId"] as? String, !child.isEmpty else { throw DSHError("session/fork-unavailable") }
        let projections = (try? await rpc("session/projections", ["request": ["sessionId": child]])) as? [String: Any]
        let values = projections?["values"] as? [String: Any] ?? [:]
        let inbox = values["inbox"] as? [String: Any] ?? [:]
        for target in ["next-step", "next-turn"] {
            for queued in inbox[target] as? [[String: Any]] ?? [] {
                guard let id = queued["id"] as? String else { continue }
                _ = try? await rpc("session/updateQueue", ["request": ["sessionId": child, "itemId": id, "action": ["kind": "remove"]]])
            }
        }
        var title: String?
        if let inherited = values["title"] as? String, !inherited.trimmingCharacters(in: .whitespaces).isEmpty {
            let base = sourceTitle.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? inherited
            let bumped = Self.bumpedForkTitle(base)
            if (try? await renameSession(child, title: bumped)) != nil { title = bumped }
        }
        return ForkOutcome(sessionId: child, title: title)
    }

    /// `T` → `T (1)`, `T (1)` → `T (2)`, `T（1）` → `T（2）`.
    public static func bumpedForkTitle(_ title: String) -> String {
        for (open, close) in [("(", ")"), ("（", "）")] where title.hasSuffix(close) {
            if let start = title.range(of: open, options: .backwards),
               let number = Int(title[start.upperBound..<title.index(before: title.endIndex)]) {
                return String(title[..<start.upperBound]) + String(number + 1) + close
            }
        }
        return title + " (1)"
    }
}

public enum ForkPoints {
    static let normalEnds: Set<String> = ["completed", "aborted", "interrupted", "max-tokens", "blocked", "forked", "unknown"]

    /// The `turn/end` of the turn the reply at `replySeq` closes, or nil when
    /// something transcript-visible follows it (official web client's rule).
    public static func afterReply(_ events: [LogEvent], replySeq: Int) -> Int? {
        var found = false
        for event in events {
            if !found {
                if event.seq < replySeq { continue }
                guard event.seq == replySeq, case .assistantMessage(_, _, _, let message, _) = event,
                      !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                found = true
                continue
            }
            switch event {
            case .turnEnded(let seq, _, let reason): return normalEnds.contains(reason) ? seq : nil
            case .assistantMessage, .toolResult: return nil
            case .retry: return nil
            case .other(_, let type) where type == "tool/call": return nil
            default: continue
            }
        }
        return nil
    }

    /// The last event before the prompt at `promptSeq` that did not deliver it.
    public static func beforePrompt(_ events: [LogEvent], promptSeq: Int) -> Int? {
        let before = events.filter { $0.seq < promptSeq }
        var expected = promptSeq - 1
        for event in before.reversed() {
            guard event.seq == expected else { return nil }
            expected -= 1
            if !deliversPrompt(event) { return event.seq }
        }
        return nil
    }

    private static func deliversPrompt(_ event: LogEvent) -> Bool {
        switch event {
        case .turnStarted: return true
        case .other(_, let type): return ["agent/inbox/spliced", "step/start", "system/message"].contains(type)
        default: return false
        }
    }
}
