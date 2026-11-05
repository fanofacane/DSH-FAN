// SPDX-License-Identifier: AGPL-3.0-or-later
// Trace event inputs from DSH Go packages/dsh_client/lib/src/{models,transcript}.dart.
// Projection fields from DSH Go app/lib/state/usage_state.dart.
import Foundation

public struct RunFact: Identifiable, Equatable, Sendable {
    enum Detail: Equatable, Sendable {
        case turnStarted, turnEnded(String), stepStarted, boundary
        case message(TraceModel), attempt(Date?), retry(String)
        case toolCall(ToolCall), toolResult(String, TraceToolResult)
        case approvalAsked(String, callId: String?), approvalDecided(String, TraceApproval)
        case other
    }

    public let id: Int
    public let time: Date
    public let kind: String
    public let turn: Int?
    public let toolName: String?
    let step: Int?
    let detail: Detail

    public init?(_ raw: Any?) {
        self.init(raw, log: LogEvent.parse(raw))
    }

    init?(_ raw: Any?, log: LogEvent?) {
        guard let event = raw as? [String: Any], let seq = tokenCount(event["seq"]),
              let time = Self.timestamp(event["time"]), let kind = event["type"] as? String else { return nil }
        let data = event["data"] as? [String: Any] ?? [:]
        id = seq
        self.time = time
        self.kind = kind
        turn = tokenCount(data["turn"])
        step = tokenCount(data["step"])
        toolName = data["name"] as? String ?? data["toolName"] as? String

        switch log {
        case .turnStarted: detail = .turnStarted
        case .turnEnded(_, _, let reason): detail = .turnEnded(reason)
        case .userMessage: detail = .boundary
        case .attempt: detail = .attempt(Self.streamBounds(data["stream"]).first)
        case .retry(_, _, _, let code): detail = .retry(code)
        case .assistantMessage(_, _, _, let message, let interrupted):
            let source = (data["message"] as? [String: Any])?["source"] as? [String: Any]
            let bounds = Self.streamBounds(data["stream"])
            detail = .message(TraceModel(provider: source?["provider"] as? String, model: source?["model"] as? String,
                                         firstToken: bounds.first, lastToken: bounds.last, usage: TraceUsage(data["usage"]),
                                         hasText: !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                         hasReasoning: !message.reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                         toolCalls: message.toolCalls.count, interrupted: interrupted))
        case .toolResult(_, let callId, let text, let failed, let presentation):
            let error = data["error"] as? [String: Any]
            detail = .toolResult(callId, TraceToolResult(seq: seq, text: text, failed: failed,
                                                         failureCode: error?["code"] as? String, failureReason: error?["reason"] as? String,
                                                         presentation: presentation))
        default:
            switch kind {
            case "step/start": detail = .stepStarted
            case "step/end": detail = .boundary
            case "tool/call":
                if let id = data["callId"] as? String, !id.isEmpty {
                    detail = .toolCall(ToolCall(id: id, name: toolName ?? "", arguments: data["arguments"] as? String ?? ""))
                } else { detail = .other }
            case "approval/asked":
                detail = (data["id"] as? String).map { .approvalAsked($0, callId: data["callId"] as? String) } ?? .other
            case "approval/decided":
                let outcome = TraceApproval(rawValue: data["outcome"] as? String ?? "") ?? .unknown
                detail = (data["id"] as? String).map { .approvalDecided($0, outcome) } ?? .other
            default: detail = .other
            }
        }
    }

    private static func timestamp(_ value: Any?) -> Date? {
        guard let millis = number(value), millis.isFinite else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }

    private static func number(_ value: Any?) -> Double? {
        switch JSONValue(value) {
        case .integer(let value): return Double(value)
        case .number(let value): return value
        default: return nil
        }
    }

    /// Inspect only the timestamps in compact assistant streams. No delta expansion.
    private static func streamBounds(_ raw: Any?) -> (first: Date?, last: Date?) {
        var first: Date?, last: Date?
        func see(_ time: Date) {
            first = min(first ?? time, time)
            last = max(last ?? time, time)
        }
        for record in raw as? [[String: Any]] ?? [] {
            switch record["type"] as? String {
            case "chunk":
                let chunk = record["chunk"] as? [String: Any]
                if let type = chunk?["type"] as? String, ["text-delta", "reasoning-delta", "tool-call-delta"].contains(type),
                   let time = timestamp(record["time"]) { see(time) }
            case "text-chunks", "reasoning-chunks", "tool-call-chunks":
                guard let time = timestamp(record["time0"]) else { continue }
                see(time)
                let delta = (record["dt"] as? [Any] ?? []).compactMap(number).reduce(0, +)
                if delta.isFinite { see(time.addingTimeInterval(delta / 1000)) }
            default: break
            }
        }
        return (first, last)
    }
}

public struct SessionMetrics {
    private let tokens: [String: Any]
    private let pressure: [String: Any]
    private let breakdown: [String: Any]
    private let stats: [String: Any]

    public init(_ values: [String: Any]) {
        tokens = values["tokenUsage"] as? [String: Any] ?? [:]
        pressure = values["contextPressure"] as? [String: Any] ?? [:]
        breakdown = values["contextBreakdown"] as? [String: Any] ?? [:]
        stats = values["sessionStats"] as? [String: Any] ?? [:]
    }

    public var input: Int? {
        let counts = [uncached, cacheRead, cacheWrite].compactMap { $0 }
        return counts.isEmpty ? nil : sumTokens(counts)
    }
    public var output: Int? { tokenCount(tokens["outputTokens"]) }
    public var total: Int? {
        guard let input, let output else { return nil }
        return sumTokens([input, output])
    }
    public var uncached: Int? { tokenCount(tokens["uncachedInputTokens"]) }
    public var cacheRead: Int? { tokenCount(tokens["cacheReadTokens"]) }
    public var cacheWrite: Int? { tokenCount(tokens["cacheWriteTokens"]) }
    public var cacheHitRate: Double? {
        guard let cacheRead, let input, input > 0 else { return nil }
        return Double(cacheRead) / Double(input)
    }
    public var pressureTokens: Int? { tokenCount(pressure["pressureTokens"]) }
    public var projectedTokens: Int? { tokenCount(pressure["projectedTokens"]) }
    public var contextWindow: Int? { tokenCount(pressure["contextWindow"]) }
    public var systemTokens: Int? { tokenCount(breakdown["systemTokens"]) }
    public var toolTokens: Int? { tokenCount(breakdown["toolsTokens"]) }
    public var messageTokens: Int? { tokenCount(breakdown["messageTokens"]) }
    public var fraction: Double? {
        guard let used = pressureTokens, let window = contextWindow, window > 0 else { return nil }
        return min(1, Double(used) / Double(window))
    }
    public var turns: Int? { tokenCount(stats["turns"]) }
    public var modelMs: Int? { tokenCount(stats["llmMs"]) }
    public var toolMs: Int? { tokenCount(stats["toolMs"]) }
}
