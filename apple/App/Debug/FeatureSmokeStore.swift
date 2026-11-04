// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import DSHClient
import Foundation

extension AppSession {
    func smokeStore(_ result: FeatureSmokeContext) async throws {
        // App Store build: the engine's plugin manager must reject every probe.
        for (endpoint, code) in try await self.connection.complianceAPI.pluginManagerRejections() { result.set(endpoint, code) }
        let ids = try await self.connection.agentAPI.list().compactMap(\.id)
        result.set("presets", ids)
        guard !ids.isEmpty else { throw DSHError("E_PRESETS_MISSING") }
    }
}
#endif
