// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import DSHClient
import Foundation

extension AppSession {
    func smokeT4(_ result: FeatureSmokeContext) async throws {
        let sections = try await self.connection.settingsAPI.describe()
        guard let section = sections.first(where: { $0.id == "llm-pi-ai" }) else { throw DSHError("E_PROVIDER_ADAPTER_UNAVAILABLE") }
        let discovered = try await self.connection.providerAPI.discoverModels(settingsNs: section.id, request: ModelDiscoveryRequest(baseURL: "http://127.0.0.1:38911/v1", api: "openai-completions"))
        guard discovered.contains(where: { $0.id == "ios-smoke-model" }) else { throw DSHError("E_MODEL_DISCOVERY") }
        let route = "ios-smoke-" + UUID().uuidString.lowercased().prefix(8)
        let profile: JSONValue = ["displayName": "iOS Smoke", "baseURL": "http://127.0.0.1:38911/v1", "api": "openai-completions", "models": [["id": "ios-smoke-model"]]]
        let saved = try await self.connection.settingsAPI.mutate(ns: section.id, expectedRevision: section.revision, ops: [["op": "set", "path": ["providers", route], "value": profile.foundation]])
        do {
            try await self.connection.reloadModels()
            result.set("modelInPicker", self.connection.models.contains { $0.provider == route && $0.model == "ios-smoke-model" })
            guard result["modelInPicker"]?.bool == true else { throw DSHError("E_PROVIDER_NOT_IN_CATALOG") }
        } catch {
            _ = try? await self.connection.settingsAPI.mutate(ns: section.id, expectedRevision: saved.revision, ops: [["op": "unset", "path": ["providers", route]]])
            throw error
        }
        _ = try await self.connection.settingsAPI.mutate(ns: section.id, expectedRevision: saved.revision, ops: [["op": "unset", "path": ["providers", route]]])
        try await self.connection.reloadModels()
        result.set("discovery", true); result.set("temporaryProviderRemoved", !self.connection.models.contains { $0.provider == route })
        result.set("credentialUsed", false)
    }
}
#endif
