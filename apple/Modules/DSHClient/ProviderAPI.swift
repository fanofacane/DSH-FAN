// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct ConfigurableProvider: Sendable {
    public let provider: String?
    public let displayName: String?
    public let error: String?
    public let settingsNs: String?
    public let settingsPath: [String]?
    public let defaultBaseURL: String?
    public let declared: Bool
    init(_ row: [String: Any]) {
        provider = row["provider"] as? String; displayName = row["displayName"] as? String
        error = row["error"] as? String; settingsNs = row["settingsNs"] as? String
        settingsPath = row["settingsPath"] as? [String]; defaultBaseURL = row["defaultBaseURL"] as? String
        declared = row["declared"] as? Bool == true
    }
    public init(provider: String, displayName: String) { self.init(["provider": provider, "displayName": displayName]) }
}
public struct RegisteredProvider: Sendable {
    public let id: String?
    public let name: String?
    init(_ row: [String: Any]) { id = row["id"] as? String; name = row["name"] as? String }
}
public struct DiscoveredModel {
    public let id: String?
    /// This is a value for the engine's dynamic provider-settings schema, not a fixed app model.
    public let settingsSpec: [String: Any]
    init(_ row: [String: Any]) {
        id = row["id"] as? String
        var spec: [String: Any] = ["id": row["id"] ?? ""]
        for key in ["name", "contextWindow", "maxTokens"] { if let value = row[key] { spec[key] = value } }
        if let input = row["inputModalities"] { spec["input"] = input }
        settingsSpec = spec
    }
}
public struct ModelDiscoveryRequest: Sendable {
    public var baseURL: String?, api: String?, apiKey: String?, provider: String?
    public init(baseURL: String? = nil, api: String? = nil, apiKey: String? = nil, provider: String? = nil) {
        self.baseURL = baseURL; self.api = api; self.apiKey = apiKey; self.provider = provider
    }
    var payload: [String: Any] {
        var value: [String: Any] = [:]
        if let baseURL { value["baseURL"] = baseURL }; if let api { value["api"] = api }
        if let apiKey { value["apiKey"] = apiKey }; if let provider { value["provider"] = provider }
        return value
    }
}
public struct ProviderAPI: Sendable {
    let client: DSHClient
    public init(client: DSHClient) { self.client = client }
    public func listConfigurableProviders() async throws -> [ConfigurableProvider] {
        let value = try await client.rpc("llm/listConfigurableProviders") as? [[String: Any]] ?? []
        return value.map(ConfigurableProvider.init)
    }
    public func listProviders() async throws -> [RegisteredProvider] {
        let value = try await client.rpc("llm/listProviders") as? [[String: Any]] ?? []
        return value.map(RegisteredProvider.init)
    }
    public func discoverModels(settingsNs: String, request: ModelDiscoveryRequest) async throws -> [DiscoveredModel] {
        let value = try await client.rpc("llm/discoverModels", ["settingsNs": settingsNs, "request": request.payload]) as? [[String: Any]] ?? []
        return value.map(DiscoveredModel.init)
    }
}
public struct CredentialsAPI: Sendable {
    let client: DSHClient
    public init(client: DSHClient) { self.client = client }
    public func describe(refs: [String]) async throws -> [String: CredentialState] {
        let value = try await client.rpc("credentials/describe", ["refs": refs]) as? [String: Any] ?? [:]
        return value.mapValues { raw in
            let row = raw as? [String: Any] ?? [:]
            return CredentialState(configured: row["configured"] as? Bool == true, writable: row["writable"] as? Bool == true)
        }
    }
    public func set(ref: String, value: String) async throws { try await client.rpc("credentials/set", ["ref": ref, "value": value]) }
    public func unset(ref: String) async throws { try await client.rpc("credentials/unset", ["ref": ref]) }
}
