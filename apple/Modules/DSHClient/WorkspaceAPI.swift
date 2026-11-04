// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
public struct WorkspaceRecord: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let path: String
    public let sessionIds: [String]
    public init?(_ row: [String: Any]) {
        guard let id = row["workspaceId"] as? String, !id.isEmpty else { return nil }
        self.id = id; title = row["title"] as? String ?? id
        path = row["path"] as? String ?? ""; sessionIds = row["sessionIds"] as? [String] ?? []
    }
}
public struct WorkspaceState {
    public private(set) var items: [WorkspaceRecord] = []
    public private(set) var archived: Set<String> = []
    public private(set) var pinned: [String] = []
    public init() {}
    mutating func apply(_ frame: [String: Any]) {
        switch frame["type"] as? String {
        case "baseline", "replace":
            let value = frame["value"] as? [String: Any] ?? [:]
            items = (value["items"] as? [[String: Any]] ?? []).compactMap(WorkspaceRecord.init)
            archived = Set(value["archivedSessionIds"] as? [String] ?? [])
            pinned = value["pinnedSessionIds"] as? [String] ?? []
        case "upsert":
            guard let raw = frame["workspace"] as? [String: Any], let record = WorkspaceRecord(raw) else { return }
            if let index = items.firstIndex(where: { $0.id == record.id }) { items[index] = record } else { items.insert(record, at: 0) }
        case "remove": items.removeAll { $0.id == frame["workspaceId"] as? String }
        case "order":
            let order = frame["workspaceIds"] as? [String] ?? []
            items.sort { (order.firstIndex(of: $0.id) ?? Int.max) < (order.firstIndex(of: $1.id) ?? Int.max) }
        case "archived": archived = Set(frame["archivedSessionIds"] as? [String] ?? [])
        case "pinned": pinned = frame["pinnedSessionIds"] as? [String] ?? []
        default: break
        }
    }
}

/// A mux payload is immutable and only the client module interprets its wire keys.
public struct WorkspaceEvent: @unchecked Sendable {
    let value: [String: Any]
    init(_ value: [String: Any]) { self.value = value }
}
extension WorkspaceState {
    public mutating func apply(_ event: WorkspaceEvent) { apply(event.value) }
    public mutating func setPinned(_ ids: [String]) { pinned = ids }
    public mutating func setArchived(_ ids: [String]) { archived = Set(ids) }
}

public struct DirectoryLocation: Sendable {
    public let name: String
    public let path: String?
    init(_ value: [String: Any]) { name = value["name"] as? String ?? ""; path = value["path"] as? String }
}
public struct DirectoryListing: Sendable {
    public let path: String?
    public let crumbs: [DirectoryLocation]
    public let entries: [DirectoryLocation]
    public let truncated: Bool
    public init() { self.init([:]) }
    init(_ row: [String: Any]) {
        path = row["path"] as? String
        crumbs = (row["crumbs"] as? [[String: Any]] ?? []).map(DirectoryLocation.init)
        entries = (row["entries"] as? [[String: Any]] ?? []).map(DirectoryLocation.init)
        truncated = row["truncated"] as? Bool == true
    }
}

public struct WorkspaceAPI: Sendable {
    let client: DSHClient
    public init(client: DSHClient) { self.client = client }
    public func follow() async throws -> AsyncThrowingStream<WorkspaceEvent, Error> {
        try await client.domainStream("workspace/follow", decode: { WorkspaceEvent($0) })
    }
    public func create(path: String) async throws -> WorkspaceRecord {
        let response = try await client.rpc("workspace/create", ["request": ["path": path]]) as? [String: Any] ?? [:]
        guard let row = response["workspace"] as? [String: Any], let workspace = WorkspaceRecord(row) else { throw DSHError("E_WORKSPACE_RESPONSE") }
        return workspace
    }
    public func rename(workspaceId: String, title: String) async throws {
        try await client.rpc("workspace/rename", ["request": ["workspaceId": workspaceId, "title": title]])
    }
    public func delete(workspaceId: String) async throws { try await client.rpc("workspace/delete", ["request": ["workspaceId": workspaceId]]) }
    public func pinSession(sessionId: String) async throws -> [String] { try await sessionOrder("pinSession", sessionId, key: "pinnedSessionIds") }
    public func unpinSession(sessionId: String) async throws -> [String] { try await sessionOrder("unpinSession", sessionId, key: "pinnedSessionIds") }
    public func archiveSession(sessionId: String, stopActivity: Bool) async throws -> [String] {
        try await sessionOrder("archiveSession", sessionId, key: "archivedSessionIds", stopActivity: stopActivity)
    }
    public func unarchiveSession(sessionId: String) async throws -> [String] { try await sessionOrder("unarchiveSession", sessionId, key: "archivedSessionIds") }
    private func sessionOrder(_ operation: String, _ id: String, key: String, stopActivity: Bool? = nil) async throws -> [String] {
        var request: [String: Any] = ["sessionId": id]
        if let stopActivity { request["stopActivity"] = stopActivity }
        let value = try await client.rpc("workspace/" + operation, ["request": request]) as? [String: Any] ?? [:]
        guard let ids = value[key] as? [String] else { throw DSHError("E_WORKSPACE_RESPONSE") }
        return ids
    }
    public func listDirectory(path: String? = nil) async throws -> DirectoryListing {
        let row = try await client.rpc("directoryPicker/list", path.map { ["path": $0] } ?? [:]) as? [String: Any] ?? [:]
        return DirectoryListing(row)
    }
    public func createDirectory(path: String, name: String) async throws -> String {
        guard let value = try await client.rpc("directoryPicker/createDirectory", ["path": path, "name": name]) as? String else { throw DSHError("E_DIRECTORY_CREATE") }
        return value
    }
}
