// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import DSHClient
import Foundation

extension AppSession {
    func smokeT2(_ result: FeatureSmokeContext) async throws {
        self.transcript.newChat()
        let id = try await self.transcript.ensureSession()
        let commands = try await self.connection.commandsAPI.list(agentId: id)
        guard commands.contains(where: { $0.name == "permission" }) else { throw DSHError("E_COMMAND_CATALOG") }
        let response = try await self.connection.commandsAPI.execute(agentId: id, line: "/permission danger-full-access")
        guard response.kind == "success" else { throw DSHError("E_COMMAND_EXECUTE") }
        let files = try await self.connection.filesAPI.listReferences(agentId: id, query: "")
        guard files != nil else { throw DSHError("E_REFERENCE_LIST") }
        result.set("commands", commands.count); result.set("files", files!.count); result.set("permission", true)
        self.transcript.incomingDraft = SharedDraft(text: "/", images: [])
    }
}
#endif
