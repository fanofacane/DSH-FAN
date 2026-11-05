// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct AgentPreset: Sendable {
    public let id: String?
    public let name: String?
    public let description: String?
    public let broken: String?
    public let isDefault: Bool
    /// Presence was significant to the original selection logic, including JSON null.
    public let hasBrokenField: Bool
    public init(id: String, name: String, description: String? = nil, isDefault: Bool = false) {
        var row: [String: Any] = ["id": id, "name": name, "isDefault": isDefault]
        row["description"] = description
        self.init(row)
    }
    init(_ row: [String: Any]) {
        id = row["id"] as? String; name = row["name"] as? String
        description = row["description"] as? String; broken = row["broken"] as? String
        isDefault = row["isDefault"] as? Bool == true; hasBrokenField = row["broken"] != nil
    }
}
public struct AgentDocument: Sendable {
    public let content: String?
    init(_ row: [String: Any]) { content = row["content"] as? String }
}
public struct AgentAPI: Sendable {
    let client: DSHClient
    public init(client: DSHClient) { self.client = client }
    public func list() async throws -> [AgentPreset] {
        let response = try await client.rpc("agentPresets/list") as? [String: Any] ?? [:]
        return (response["presets"] as? [[String: Any]] ?? []).map(AgentPreset.init)
    }
    public func read(agentPreset: String) async throws -> AgentDocument {
        AgentDocument(try await client.rpc("agentPresets/read", ["agentPreset": agentPreset]) as? [String: Any] ?? [:])
    }
    public func select(agentId: String, agentPreset: String) async throws { try await client.rpc("agentPresets/select", ["agentId": agentId, "agentPreset": agentPreset]) }
    public func follow(_ route: SubagentRoute) async throws -> AsyncThrowingStream<ChatEvent, Error> { try await client.follow(address: route.address) }
    public func prompt(_ route: SubagentRoute, text: String, requestId: String = UUID().uuidString, clientTimeZone: String = TimeZone.current.identifier) async throws {
        guard route.canPrompt else { throw DSHError("E_SUBAGENT_READ_ONLY") }
        try await client.rpc("subagents/prompt", ["request": ["requestId": requestId,
            "parentSessionId": route.parent, "childSessionId": route.id, "mode": "continuable", "delivery": "queue",
            "content": [["type": "text", "text": text]], "clientTimeZone": clientTimeZone]])
    }
    public func interruptByParent(_ route: SubagentRoute) async throws {
        guard route.canPrompt else { throw DSHError("E_SUBAGENT_READ_ONLY") }
        try await client.rpc("subagents/interruptByParent", ["parentSessionId": route.parent, "childSessionId": route.id, "mode": "continuable"])
    }
}
