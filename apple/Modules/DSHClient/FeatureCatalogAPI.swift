// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: packages/dsh_client/lib/src/features_api.dart.
import Foundation

public struct HostSkill: Identifiable, Sendable {
    public let name: String
    public let description: String?
    public let whenToUse: String?
    public let modelInvocable: Bool
    public var id: String { name }

    public init(name: String, description: String? = nil, whenToUse: String? = nil, modelInvocable: Bool = true) {
        self.name = name
        self.description = description
        self.whenToUse = whenToUse
        self.modelInvocable = modelInvocable
    }
}

public struct HostJob: Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let status: String
    public var isRunning: Bool { ["running", "stopping"].contains(status) }

    public init(id: String, kind: String, status: String) {
        self.id = id
        self.kind = kind
        self.status = status
    }
}

public struct FeatureCatalogAPI: Sendable {
    private let client: DSHClient
    public init(client: DSHClient) { self.client = client }

    public func skills(sessionId: String) async throws -> [HostSkill] {
        let value = try await client.rpc("skills/list", ["request": ["sessionId": sessionId]]) as? [String: Any]
        var names: Set<String> = []
        return (value?["skills"] as? [[String: Any]] ?? []).compactMap { row in
            guard let name = row["name"] as? String, !name.isEmpty, names.insert(name).inserted else { return nil }
            return HostSkill(name: name, description: row["description"] as? String,
                             whenToUse: row["whenToUse"] as? String, modelInvocable: row["modelInvocable"] as? Bool != false)
        }
    }

    public func jobs(sessionId: String) async throws -> AsyncThrowingStream<[HostJob], Error> {
        try await client.domainStream("job/list", ["request": ["sessionId": sessionId]]) { value in
            var ids: Set<String> = []
            return (value["jobs"] as? [[String: Any]] ?? []).compactMap { row in
                guard let id = row["jobId"] as? String ?? row["id"] as? String, !id.isEmpty, ids.insert(id).inserted else { return nil }
                // The label may contain a full shell command with private arguments.
                return HostJob(id: id, kind: row["kind"] as? String ?? "", status: row["status"] as? String ?? "")
            }
        }
    }
}
