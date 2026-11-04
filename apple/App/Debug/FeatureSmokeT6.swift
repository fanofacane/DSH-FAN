// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import DSHClient
import Foundation

extension AppSession {
    func smokeT6(_ result: FeatureSmokeContext) async throws {
        let sections = try await self.connection.settingsAPI.describe()
        result.set("capabilityNamespaces", sections.map(\.id).filter { $0.contains("web") || $0.contains("media") })
        guard let section = sections.first(where: { $0.id == "web-search-deepseek" }),
              let previous = section.value["maxUses"] as? Int else { throw DSHError("E_SEARCH_SETTINGS_UNAVAILABLE") }
        let form = EngineFormModel(section)
        form.set(["maxUses"], previous + 1); await form.save(self)
        guard form.error == nil, form.section.value["maxUses"] as? Int == previous + 1 else { throw DSHError(form.error ?? "E_SETTINGS_WRITE") }
        form.set(["maxUses"], previous); await form.save(self)
        guard form.error == nil, form.section.value["maxUses"] as? Int == previous else { throw DSHError(form.error ?? "E_SETTINGS_RESTORE") }
        result.set("searchLimitRoundTrip", true)
        result.set("mediaInstalled", sections.contains { $0.id == "media" || $0.id == "dsh-media" })
    }
}
#endif
