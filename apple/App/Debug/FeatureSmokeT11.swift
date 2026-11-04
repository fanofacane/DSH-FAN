// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import DSHClient
import Foundation

extension AppSession {
    func smokeT11(_ result: FeatureSmokeContext) async throws {
        self.transcript.newChat(); await self.transcript.send("只回复 OK")
        try await smokeWait(seconds: 90) { !self.transcript.busy && self.transcript.items.contains { $0.role == .assistant && $0.state == .done } }
        await self.sessionList.refreshSessions()
        guard let session = self.sessionList.sessions.first(where: { $0.id == self.transcript.currentSessionId }) else { throw DSHError("E_NO_SESSION") }
        try await self.sessionList.pin(session, pinned: true)
        guard self.workspace.state.pinned.contains(session.id) else { throw DSHError("E_PIN") }
        try await self.sessionList.archive(session, archived: true)
        try await smokeWait { self.workspace.state.archived.contains(session.id) && !self.workspace.state.pinned.contains(session.id) }
        try await self.sessionList.archive(session, archived: false)
        guard !self.workspace.state.archived.contains(session.id) else { throw DSHError("E_UNARCHIVE") }
        try await self.sessionList.pin(session, pinned: true); try await self.sessionList.pin(session, pinned: false)
        guard !self.workspace.state.pinned.contains(session.id) else { throw DSHError("E_UNPIN") }
        result.set("pinArchiveRestoreUnpin", true); result.set("realModel", true)
    }
}
#endif
