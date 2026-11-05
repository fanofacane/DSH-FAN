// SPDX-License-Identifier: AGPL-3.0-or-later
// Port of traceTurns / _TurnTracer in DSH Go packages/dsh_client/lib/src/transcript.dart.
import Foundation

/// Each append visits just the new event. A snapshot starts a new cut of the log.
public struct TurnTraceFold: Sendable {
    public private(set) var completed: [TurnTrace] = []
    public private(set) var compactionStart: Date?
    private var active: TurnTracer?
    private var lastSeq = -1

    public init() {}
    public var running: TurnTrace? { active?.trace() }
    public var turns: [TurnTrace] { completed + (running.map { [$0] } ?? []) }

    public mutating func apply(_ fact: RunFact) {
        guard fact.id > lastSeq else { return }
        lastSeq = fact.id
        switch fact.kind {
        case "compaction/start": compactionStart = fact.time
        case "compaction/end", "turn/end": compactionStart = nil
        default: break
        }
        switch fact.detail {
        case .turnStarted:
            if let active { completed.append(active.trace(end: active.lastSeen, reason: "interrupted")) }
            active = TurnTracer(start: fact)
        case .turnEnded(let reason):
            if let active, fact.turn == nil || fact.turn == active.turn {
                completed.append(active.trace(end: fact.time, endSeq: fact.id, reason: reason))
                self.active = nil
            }
        default:
            if fact.turn == nil || fact.turn == active?.turn { active?.apply(fact) }
        }
    }
}

private struct TurnTracer: Sendable {
    let turn: Int
    let start: RunFact
    private var boundary: Date
    private(set) var lastSeen: Date
    private var lastStep = 0
    private var spans: [TraceSpan] = []
    private var stepStarts: [Int: Date] = [:]
    private var attemptFirstToken: [Int: Date] = [:]
    private var retries: [Int: [String]] = [:]
    private var tools: [String: TraceSpan] = [:]
    private var approvals: [String: TraceSpan] = [:]

    init(start: RunFact) {
        self.start = start
        turn = start.turn ?? 0
        boundary = start.time
        lastSeen = start.time
    }

    mutating func apply(_ fact: RunFact) {
        lastSeen = max(lastSeen, fact.time)
        let step = fact.step ?? lastStep
        switch fact.detail {
        case .stepStarted:
            stepStarts[step] = fact.time
            lastStep = max(lastStep, step)
        case .attempt(let first):
            if let first { attemptFirstToken[step] = min(first, attemptFirstToken[step] ?? first) }
        case .retry(let code):
            retries[step, default: []].append(code)
        case .message(var model):
            lastStep = max(lastStep, step)
            if let first = attemptFirstToken.removeValue(forKey: step) {
                model.firstToken = min(first, model.firstToken ?? first)
            }
            model.retries = retries.removeValue(forKey: step) ?? []
            spans.append(TraceSpan(kind: .model, step: step, seq: fact.id,
                                   start: stepStarts.removeValue(forKey: step) ?? boundary, end: fact.time, model: model))
            boundary = fact.time
        case .toolCall(let call):
            tools[call.id] = TraceSpan(kind: call.name == "ask_user_question" ? .question : .tool, step: step,
                                       seq: fact.id, start: fact.time, callId: call.id, toolName: call.name,
                                       arguments: call.arguments, dispatched: fact.time)
        case .approvalAsked(let id, let callId):
            let tool = callId.flatMap { tools[$0] }
            approvals[id] = TraceSpan(kind: .approval, step: tool?.step ?? step, seq: fact.id, start: fact.time,
                                      callId: callId, toolName: fact.toolName, arguments: tool?.arguments)
        case .approvalDecided(let id, let outcome):
            guard var approval = approvals.removeValue(forKey: id) else { break }
            approval.end = fact.time
            approval.outcome = outcome
            spans.append(approval)
            if let id = approval.callId, let call = tools[id] {
                tools[id] = TraceSpan(kind: call.kind, step: call.step, seq: call.seq, start: fact.time,
                                      callId: id, toolName: call.toolName, arguments: call.arguments,
                                      dispatched: call.dispatched, outcome: outcome)
            }
        case .toolResult(let id, let result):
            let pending = approvals.filter { $0.value.callId == id }
            for (key, var approval) in pending {
                approval.end = fact.time
                approval.cutShort = true
                spans.append(approval)
                approvals.removeValue(forKey: key)
            }
            if var call = tools.removeValue(forKey: id), pending.isEmpty {
                call.end = fact.time
                call.result = result
                spans.append(call)
            }
            boundary = fact.time
        case .boundary:
            boundary = max(boundary, fact.time)
        default: break
        }
    }

    func trace(end: Date? = nil, endSeq: Int? = nil, reason: String? = nil) -> TurnTrace {
        let waiting = Set(approvals.values.compactMap(\.callId))
        var inFlight = Array(approvals.values) + tools.values.filter {
            $0.callId.map { !waiting.contains($0) } ?? true
        }
        inFlight += stepStarts.map { modelSpan(step: $0.key, start: $0.value) }
        if end == nil, inFlight.isEmpty {
            let next = lastStep < Int.max ? lastStep + 1 : lastStep
            let step = max(next, retries.keys.max() ?? 0, attemptFirstToken.keys.max() ?? 0)
            inFlight.append(modelSpan(step: step, start: boundary))
        }
        let unfinished = inFlight.map { span in
            var span = span
            span.end = end
            span.cutShort = end != nil
            return span
        }
        let ordered = (spans + unfinished).sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.seq != $1.seq {
                return ($0.seq < 0 ? Int.max : $0.seq) < ($1.seq < 0 ? Int.max : $1.seq)
            }
            return $0.step < $1.step
        }
        return TurnTrace(turn: turn, startSeq: start.id, start: start.time, endSeq: endSeq,
                         end: end, endReason: reason, spans: ordered)
    }

    private func modelSpan(step: Int, start: Date) -> TraceSpan {
        var model = TraceModel()
        model.firstToken = attemptFirstToken[step]
        model.retries = retries[step] ?? []
        return TraceSpan(kind: .model, step: step, seq: -1, start: start, model: model)
    }
}
