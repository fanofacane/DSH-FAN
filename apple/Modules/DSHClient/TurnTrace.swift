// SPDX-License-Identifier: AGPL-3.0-or-later
// Port of TraceKind, TraceUsage, TraceSpan and TurnTrace in
// DSH Go packages/dsh_client/lib/src/transcript.dart.
import Foundation

public enum TraceKind: Sendable { case model, tool, approval, question }

public struct TraceUsage: Equatable, Sendable {
    public let uncachedInput: Int?
    public let cacheRead: Int?
    public let cacheWrite: Int?
    public let output: Int?
    public let reasoning: Int?
    public let input: Int?
    public let requests: Int

    public var total: Int? {
        guard let input, let output else { return nil }
        return sumTokens([input, output])
    }

    public var cacheHitRate: Double? {
        guard let cacheRead, let input, input > 0 else { return nil }
        return Double(cacheRead) / Double(input)
    }

    init?(_ value: Any?) {
        guard let raw = value as? [String: Any] else { return nil }
        uncachedInput = tokenCount(raw["inputTokens"])
        cacheRead = tokenCount(raw["cacheReadTokens"])
        cacheWrite = tokenCount(raw["cacheWriteTokens"])
        output = tokenCount(raw["outputTokens"])
        reasoning = tokenCount(raw["reasoningTokens"])
        guard uncachedInput != nil || output != nil else { return nil }
        // Providers can omit zero-valued cache fields. They remain absent
        // individually, but do not prevent computing billed input.
        if let uncachedInput {
            input = sumTokens([uncachedInput, cacheRead ?? 0, cacheWrite ?? 0])
        } else { input = nil }
        requests = 1
    }

    init(_ samples: [TraceUsage]) {
        requests = samples.count
        func sum(_ field: KeyPath<TraceUsage, Int?>, requireAll: Bool = false) -> Int? {
            let values = samples.compactMap { $0[keyPath: field] }
            guard !values.isEmpty, !requireAll || values.count == samples.count else { return nil }
            return sumTokens(values)
        }
        uncachedInput = sum(\.uncachedInput, requireAll: true)
        cacheRead = sum(\.cacheRead)
        cacheWrite = sum(\.cacheWrite)
        output = sum(\.output, requireAll: true)
        reasoning = sum(\.reasoning)
        input = sum(\.input, requireAll: true)
    }
}

func tokenCount(_ value: Any?) -> Int? {
    guard case .integer(let count) = JSONValue(value), count >= 0 else { return nil }
    return count
}

func sumTokens(_ values: [Int]) -> Int? {
    var total = 0
    for value in values {
        let next = total.addingReportingOverflow(value)
        guard !next.overflow else { return nil }
        total = next.partialValue
    }
    return total
}

public struct TraceModel: Equatable, Sendable {
    public var provider: String?
    public var model: String?
    public var firstToken: Date?
    public var lastToken: Date?
    public var usage: TraceUsage?
    public var retries: [String] = []
    public var hasText = false
    public var hasReasoning = false
    public var toolCalls = 0
    public var interrupted = false
}

public enum TraceApproval: String, Sendable {
    case allowedOnce = "allowed-once"
    case rejected, cancelled, unavailable, unknown

    var blocksTool: Bool { self == .rejected || self == .cancelled || self == .unavailable }
}

public struct TraceToolResult: Equatable, Sendable {
    public let seq: Int
    public let text: String
    public let failed: Bool
    public let failureCode: String?
    let failureReason: String?
    public let presentation: ToolPresentation
}

public struct TraceSpan: Identifiable, Equatable, Sendable {
    public struct ID: Hashable, Sendable {
        let seq: Int
        let step: Int
    }
    public var id: ID { ID(seq: seq, step: step) }
    public let kind: TraceKind
    public let step: Int
    public let seq: Int
    public let start: Date
    public var end: Date?
    public var cutShort = false
    public var model: TraceModel?
    public var callId: String?
    public var toolName: String?
    public var arguments: String?
    public var dispatched: Date?
    public var outcome: TraceApproval?
    public var result: TraceToolResult?

    public var open: Bool { end == nil }
    public var waiting: Bool { kind == .approval || kind == .question }
    public var failed: Bool { result?.failed == true || outcome?.blocksTool == true }
    public var duration: TimeInterval? { elapsed(to: end) }
    public var ttft: TimeInterval? { elapsed(to: model?.firstToken) }
    public var decoding: TimeInterval? {
        guard let first = model?.firstToken, let last = end ?? model?.lastToken, last >= first else { return nil }
        return last.timeIntervalSince(first)
    }
    public var tokensPerSecond: Double? {
        guard let output = model?.usage?.output, output > 0, let decoding, decoding >= 0.2 else { return nil }
        return Double(output) / decoding
    }

    private func elapsed(to time: Date?) -> TimeInterval? {
        guard let time, time >= start else { return nil }
        return time.timeIntervalSince(start)
    }
}

public struct TurnTrace: Identifiable, Equatable, Sendable {
    public var id: Int { startSeq }
    public let turn: Int
    public let startSeq: Int
    public let start: Date
    public let endSeq: Int?
    public let end: Date?
    public let endReason: String?
    /// In host start-time order, with sequence numbers breaking ties.
    public let spans: [TraceSpan]
    public let steps: Int
    public let usage: TraceUsage
    public let changes: [TurnFileChange]
    public var running: Bool { end == nil }
    public var duration: TimeInterval? {
        guard let end, end >= start else { return nil }
        return end.timeIntervalSince(start)
    }
    public var ttft: TimeInterval? { spans.first { $0.kind == .model }?.ttft }
    public var current: TraceSpan? { running ? spans.last { $0.open } : nil }
    public var modelTime: TimeInterval? { sum { $0.kind == .model } }
    public var toolTime: TimeInterval? { sum { $0.kind == .tool } }
    public var waitTime: TimeInterval? { sum { $0.waiting } }

    init(turn: Int, startSeq: Int, start: Date, endSeq: Int?, end: Date?, endReason: String?, spans: [TraceSpan]) {
        self.turn = turn
        self.startSeq = startSeq
        self.start = start
        self.endSeq = endSeq
        self.end = end
        self.endReason = endReason
        self.spans = spans
        let models = spans.filter { $0.kind == .model && $0.seq >= 0 }
        steps = models.count
        usage = TraceUsage(models.compactMap { $0.model?.usage })
        changes = end == nil ? [] : TurnFileChange.collect(spans)
    }

    private func sum(_ include: (TraceSpan) -> Bool) -> TimeInterval? {
        let durations = spans.filter(include).compactMap(\.duration)
        return durations.isEmpty ? nil : durations.reduce(0, +)
    }
}
