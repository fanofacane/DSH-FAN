// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
public struct RunFact: Identifiable, Equatable, Sendable {
    public let id: Int
    public let time: Date
    public let kind: String
    public let turn: Int?
    public let toolName: String?
    public init?(_ raw: Any?) {
        guard let event = raw as? [String: Any], let seq = event["seq"] as? Int, seq >= 0,
              let millis = event["time"] as? Double, millis.isFinite,
              let kind = event["type"] as? String,
              ["user/message", "turn/start", "turn/end", "step/start", "step/end", "assistant/attempt", "assistant/message", "tool/call", "tool/result", "llm/retry", "compaction/start", "compaction/end"].contains(kind) else { return nil }
        let data = event["data"] as? [String: Any] ?? [:]
        id = seq; time = Date(timeIntervalSince1970: millis / 1000); self.kind = kind
        turn = data["turn"] as? Int; toolName = data["name"] as? String
    }
}
public struct SessionMetrics {
    private let tokens: [String: Any]
    private let pressure: [String: Any]
    private let stats: [String: Any]
    public init(_ values: [String: Any]) {
        tokens = values["tokenUsage"] as? [String: Any] ?? [:]
        pressure = values["contextPressure"] as? [String: Any] ?? [:]
        stats = values["sessionStats"] as? [String: Any] ?? [:]
    }
    public var input: Int? {
        guard !tokens.isEmpty else { return nil }
        var total = 0
        for key in ["uncachedInputTokens", "cacheReadTokens", "cacheWriteTokens"] {
            let result = total.addingReportingOverflow(tokens[key] as? Int ?? 0)
            guard !result.overflow else { return nil }; total = result.partialValue
        }
        return total
    }
    public var output: Int? { tokens["outputTokens"] as? Int }
    public var uncached: Int? { tokens["uncachedInputTokens"] as? Int }
    public var cacheRead: Int? { tokens["cacheReadTokens"] as? Int }
    public var cacheWrite: Int? { tokens["cacheWriteTokens"] as? Int }
    public var pressureTokens: Int? { pressure["pressureTokens"] as? Int }
    public var projectedTokens: Int? { pressure["projectedTokens"] as? Int }
    public var contextWindow: Int? { pressure["contextWindow"] as? Int }
    public var fraction: Double? {
        guard let used = pressureTokens, let window = contextWindow, window > 0 else { return nil }
        return min(1, max(0, Double(used) / Double(window)))
    }
    public var turns: Int? { stats["turns"] as? Int }
    public var modelMs: Int? { stats["llmMs"] as? Int }
    public var toolMs: Int? { stats["toolMs"] as? Int }
}
