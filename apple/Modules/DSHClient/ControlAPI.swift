// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// A new baseline replaces the preceding connection's projections. Several keys
/// may share a sequence number, so track revisions independently for each key.
public struct SessionControlState {
    public private(set) var values: [String: SessionProjection] = [:]
    private var baselineSeq: [String: Int] = [:]
    private var revisions: [String: [String: Int]] = [:]
    public init() {}
    #if DEBUG
    public mutating func applyFixture(_ data: Data) {
        if let frame = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { apply(frame) }
    }
    #endif

    mutating func apply(_ frame: [String: Any]) {
        if frame["type"] as? String == "baseline" {
            values = [:]; baselineSeq = [:]; revisions = [:]
            let projections = (frame["value"] as? [String: Any])?["projections"] as? [String: [String: Any]] ?? [:]
            for (id, projection) in projections {
                values[id] = SessionProjection(projection["values"] as? [String: Any] ?? [:])
                baselineSeq[id] = projection["asOfSeq"] as? Int ?? -1
            }
            return
        }
        guard let id = frame["sessionId"] as? String, let key = frame["key"] as? String,
              let seq = frame["seq"] as? Int, seq >= (baselineSeq[id] ?? -1),
              seq >= (revisions[id]?[key] ?? -1) else { return }
        values[id, default: SessionProjection()].raw[key] = frame["value"] ?? NSNull()
        revisions[id, default: [:]][key] = seq
    }
}

public struct GoalState {
    public let id: String
    public let revision: Int
    public let objective: String
    public let phase: String
    public let rounds: Int
    public let maximum: Int
    public let blockedReason: String?
    public init?(_ value: Any?) {
        guard let projection = value as? [String: Any], let goal = projection["goal"] as? [String: Any],
              let id = goal["id"] as? String, let revision = goal["revision"] as? Int,
              let objective = goal["objective"] as? String, let phase = goal["phase"] as? String else { return nil }
        self.id = id; self.revision = revision; self.objective = objective; self.phase = phase
        rounds = projection["roundsStarted"] as? Int ?? 0; maximum = goal["maxGoalRounds"] as? Int ?? 0
        blockedReason = (goal["blockedReason"] as? [String: Any])?["message"] as? String
    }
}

public struct TodoItem: Sendable {
    public let content: String
    public let status: String?
    init(_ row: [String: Any]) { self.init(content: row["content"] as? String ?? "", status: row["status"] as? String) }
    public init(content: String, status: String?) { self.content = content; self.status = status }
}
/// The module retains unknown projection keys; App consumers see domain values.
public struct SessionProjection {
    fileprivate var raw: [String: Any]
    public init() { raw = [:] }
    init(_ raw: [String: Any]) { self.raw = raw }
    public var title: String? { raw["title"] as? String }
    public var todos: [TodoItem] { (raw["todos"] as? [[String: Any]] ?? []).map(TodoItem.init) }
    public var goal: GoalState? { GoalState(raw["goal"]) }
    public var metrics: SessionMetrics { SessionMetrics(raw) }
    public var hasActiveSubagentTiming: Bool { ((raw["subagentTiming"] as? [String: Any])?["active"] as? [String: Any]) != nil }
    public func subagents(parent: String) -> [SubagentRoute] {
        (raw["subagentCatalog"] as? [[String: Any]] ?? []).compactMap { SubagentRoute($0, parent: parent) }
    }
}
public struct SessionControlEvent: @unchecked Sendable {
    let value: [String: Any]
    init(_ value: [String: Any]) { self.value = value }
}
extension SessionControlState {
    public mutating func apply(_ event: SessionControlEvent) { apply(event.value) }
}
public enum GoalOperation: String, Sendable { case pause, resume, clear, edit, complete }
public struct ControlAPI: Sendable {
    let client: DSHClient
    public init(client: DSHClient) { self.client = client }
    public func follow() async throws -> AsyncThrowingStream<SessionControlEvent, Error> {
        try await client.domainStream("session/control", decode: { SessionControlEvent($0) })
    }
    public func createGoal(agentId: String, objective: String, maxGoalRounds: Int) async throws {
        try await client.rpc("goals/create", ["agentId": agentId, "request": ["objective": objective, "maxGoalRounds": maxGoalRounds]])
    }
    public func changeGoal(_ operation: GoalOperation, agentId: String, ref: GoalState, objective: String? = nil) async throws {
        var args: [String: Any] = ["agentId": agentId, "ref": ["id": ref.id, "revision": ref.revision]]
        if let objective { args["request"] = ["objective": objective] }
        try await client.rpc("goals/" + operation.rawValue, args)
    }
}
