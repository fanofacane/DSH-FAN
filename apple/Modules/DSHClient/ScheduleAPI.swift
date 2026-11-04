// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
public struct ScheduleEntry: Identifiable {
    public let taskId: String
    public let sessionId: String
    public let title: String
    public let prompt: String
    public let kind: String
    public let active: Bool
    let expected: [String: Any]
    public var id: String { sessionId + "/" + taskId }
    public init?(_ row: [String: Any]) {
        guard let id = row["id"] as? String, !id.isEmpty, let session = row["sessionId"] as? String else { return nil }
        taskId = id; sessionId = session; prompt = row["prompt"] as? String ?? ""
        title = row["title"] as? String ?? prompt.components(separatedBy: .newlines).first ?? id
        kind = row["kind"] as? String ?? "at"; active = row["status"] as? String != "inactive"
        var record = row
        for key in ["sessionId", "status", "lastDelivery"] { record[key] = nil }
        expected = record
    }
    public static func date(_ raw: Any?) -> Date? {
        guard let text = raw as? String else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]; return formatter.date(from: text)
    }
}

public enum ScheduleChange: Sendable {
    case every(seconds: Int), at(date: String, time: String, timeZone: String)
    case daily(time: String, timeZone: String), weekly(time: String, timeZone: String, weekdays: [Int])
    case cron(expression: String, timeZone: String)
    var payload: [String: Any] {
        switch self {
        case .every(let seconds): ["kind": "every", "every_seconds": seconds]
        case .at(let date, let time, let zone): ["kind": "at", "at": ["date": date, "time": time, "time_zone": zone]]
        case .daily(let time, let zone): ["kind": "daily", "daily": ["time": time, "time_zone": zone]]
        case .weekly(let time, let zone, let days): ["kind": "weekly", "weekly": ["time": time, "time_zone": zone, "weekdays": days]]
        case .cron(let expression, let zone): ["kind": "cron", "cron": ["expression": expression, "time_zone": zone]]
        }
    }
}
extension ScheduleEntry {
    public var timeZone: String? { expected["timeZone"] as? String }
    public var everySeconds: Int? { expected["everySeconds"] as? Int }
    public var expression: String? { expected["expression"] as? String }
    public var weekdays: [Int]? { expected["weekdays"] as? [Int] }
    public var scheduledAt: Date? { Self.date(expected["scheduledAt"]) }
    public var time: String? { expected["time"] as? String }
}
public struct ScheduleDelivery: Sendable {
    public let deliveredAt: Date?
    public let prompt: String?
    init(_ row: [String: Any]) { deliveredAt = ScheduleEntry.date(row["deliveredAt"]); prompt = row["prompt"] as? String }
}
public struct ScheduleHistory: Sendable {
    public let records: [ScheduleDelivery]?
    public let nextBefore: String?
    public let earlierRecordsPruned: Bool
    init(_ row: [String: Any]) {
        records = (row["records"] as? [[String: Any]])?.map(ScheduleDelivery.init)
        nextBefore = row["nextBefore"] as? String; earlierRecordsPruned = row["earlierRecordsPruned"] as? Bool == true
    }
}
public struct ScheduleAPI: Sendable {
    let client: DSHClient
    public init(client: DSHClient) { self.client = client }
    public func catalog() async throws -> [ScheduleEntry] {
        let rows = try await client.rpc("schedule/catalog") as? [[String: Any]] ?? []
        return rows.compactMap(ScheduleEntry.init)
    }
    public func update(_ task: ScheduleEntry, title: String, prompt: String, change: ScheduleChange? = nil) async throws -> ScheduleEntry {
        var request: [String: Any] = ["sessionId": task.sessionId, "id": task.taskId, "expected": task.expected, "title": title, "prompt": prompt]
        if let change { request["change"] = change.payload }
        let response = try await client.rpc("schedule/update", ["request": request]) as? [String: Any] ?? [:]
        if let code = response["code"] as? String { throw DSHError(code) }
        guard var record = response["record"] as? [String: Any] else { throw DSHError("E_SCHEDULE_RESPONSE") }
        record["sessionId"] = task.sessionId; record["status"] = task.active ? "active" : "inactive"
        guard let value = ScheduleEntry(record) else { throw DSHError("E_SCHEDULE_RESPONSE") }; return value
    }
    @discardableResult public func delete(_ task: ScheduleEntry) async throws -> Bool {
        let response = try await client.rpc("schedule/delete", ["request": ["sessionId": task.sessionId, "id": task.taskId]]) as? [String: Any] ?? [:]
        if let code = response["code"] as? String { throw DSHError(code) }
        guard let deleted = response["deleted"] as? Bool else { throw DSHError("E_SCHEDULE_RESPONSE") }; return deleted
    }
    public func history(sessionId: String, id: String, limit: Int = 20, before: String? = nil) async throws -> ScheduleHistory {
        var request: [String: Any] = ["sessionId": sessionId, "id": id, "limit": limit]
        if let before { request["before"] = before }
        let response = try await client.rpc("schedule/history", ["request": request]) as? [String: Any] ?? [:]
        if let code = response["code"] as? String { throw DSHError(code) }; return ScheduleHistory(response)
    }
}
