// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct WorkspaceFileEntry: Sendable {
    public let name: String
    public let type: String?
    public let size: Int?
    init(_ row: [String: Any]) { name = row["name"] as? String ?? ""; type = row["type"] as? String; size = row["size"] as? Int }
}
public struct WorkspaceFileListing: Sendable {
    public let entries: [WorkspaceFileEntry]
    public let truncated: Bool
    public init() { self.init([:]) }
    init(_ row: [String: Any]) { entries = (row["entries"] as? [[String: Any]] ?? []).map(WorkspaceFileEntry.init); truncated = row["truncated"] as? Bool == true }
}
public struct FileReference: Sendable {
    public let path: String?
    public let kind: String?
    init(_ row: [String: Any]) { path = row["path"] as? String; kind = row["kind"] as? String }
}
public struct FileChange: Sendable {
    public let kind: String?
    init(_ row: [String: Any]) { kind = row["kind"] as? String }
}
public struct FilesAPI: Sendable {
    let client: DSHClient
    public init(client: DSHClient) { self.client = client }
    public func list(workspaceFileScopeId: String, path: String) async throws -> WorkspaceFileListing {
        WorkspaceFileListing(try await client.rpc("workspaceFiles/list", ["workspaceFileScopeId": workspaceFileScopeId, "path": path]) as? [String: Any] ?? [:])
    }
    public func read(workspaceFileScopeId: String, path: String, offset: Int, limit: Int) async throws -> String? {
        let row = try await client.rpc("workspaceFiles/read", ["workspaceFileScopeId": workspaceFileScopeId, "path": path, "range": ["offset": offset, "limit": limit]]) as? [String: Any] ?? [:]
        return row["text"] as? String
    }
    public func changes(workspaceFileScopeId: String, path: String) async throws -> AsyncThrowingStream<FileChange, Error> {
        try await client.domainStream("workspaceFiles/changes", ["workspaceFileScopeId": workspaceFileScopeId, "path": path], decode: { FileChange($0) })
    }
    public func readBytes(workspaceFileScopeId: String, path: String) async throws -> Data { try await client.fileBytes(sessionId: workspaceFileScopeId, path: path) }
    public func renderOfficePDF(workspaceFileScopeId: String, path: String) async throws -> Data { try await client.officePDF(sessionId: workspaceFileScopeId, path: path) }
    public func attachment(sessionId: String, attachmentId: String) async throws -> Data {
        let row = try await client.rpc("session/attachment", ["request": ["sessionId": sessionId, "attachmentId": attachmentId]]) as? [String: Any]
        guard let encoded = row?["data"] as? String, let data = Data(base64Encoded: encoded) else { throw DSHError("E_IMAGE_UNAVAILABLE") }; return data
    }
    public func listReferences(agentId: String, query: String) async throws -> [FileReference]? {
        let rows = try await client.rpc("fileReferences/list", ["agentId": agentId, "query": query]) as? [[String: Any]]
        return rows?.map(FileReference.init)
    }
}
