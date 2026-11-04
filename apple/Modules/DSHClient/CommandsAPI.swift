// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct CommandEntry: Sendable {
    public let name: String?, description: String?
    public let acceptsInput: Bool
    init(_ row: [String: Any]) {
        name = row["name"] as? String; description = row["description"] as? String
        acceptsInput = row["input"] != nil && !(row["input"] is NSNull)
    }
}
public struct CommandResult: Sendable {
    public let kind: String?, text: String?
    init(_ row: [String: Any]) {
        let value = row["result"] as? [String: Any] ?? [:]
        kind = value["kind"] as? String; text = value["text"] as? String
    }
}
public struct CommandsAPI: Sendable {
    let client: DSHClient
    public init(client: DSHClient) { self.client = client }
    public func list(agentId: String) async throws -> [CommandEntry] {
        let rows = try await client.rpc("commands/list", ["agentId": agentId]) as? [[String: Any]] ?? []
        return rows.map(CommandEntry.init)
    }
    public func execute(agentId: String, line: String) async throws -> CommandResult {
        CommandResult(try await client.rpc("commands/execute", ["agentId": agentId, "line": line, "submittedAttachments": []]) as? [String: Any] ?? [:])
    }
    public func initializeDefaultModel() async throws { try await client.rpc("session/initializeDefaultModel") }
}

#if DEBUG
/// The compliance smoke may only confirm that these endpoints reject every call.
public struct StoreComplianceAPI: Sendable {
    let client: DSHClient
    public init(client: DSHClient) { self.client = client }
    public func pluginManagerRejections() async throws -> [String: String] {
        var failures: [String: String] = [:]
        for endpoint in ["pluginManager/listBundles", "pluginManager/installBundle"] {
            do {
                try await client.rpc(endpoint, endpoint.hasSuffix("installBundle") ? ["spec": "left-pad"] : [:])
                throw DSHError("E_PLUGIN_MANAGER_ACTIVE")
            } catch let error as DSHError where error.code != "E_PLUGIN_MANAGER_ACTIVE" { failures[endpoint] = error.code }
        }
        return failures
    }
}
#endif
