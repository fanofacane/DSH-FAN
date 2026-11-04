// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import Foundation
import Observation

@MainActor @Observable final class SessionListStore {
    private let shared: SessionListState
    private(set) var sessions: [SessionSummary] {
        get { shared.sessions }
        set { shared.sessions = newValue }
    }
    private let context: SessionContext
    @ObservationIgnored private weak var actions: (any SessionActions)?
    init(context: SessionContext, actions: any SessionActions) {
        self.context = context; shared = context.sessionListState; self.actions = actions
    }
    private var client: DSHClient? { context.client }
    private var workspaceAPI: WorkspaceAPI { get throws {
        guard let client else { throw DSHError("E_NOT_CONNECTED") }; return WorkspaceAPI(client: client)
    } }
    func reset() { sessions = [] }
    func insert(_ session: SessionSummary) { if !sessions.contains(where: { $0.id == session.id }) { sessions.insert(session, at: 0) } }
    func refreshSessions() async {
        guard let client, let list = try? await client.listSessions() else { return }
        sessions = list.filter { !$0.blank || $0.id == context.currentSessionId }
    }
    func pin(_ session: SessionSummary, pinned: Bool) async throws {
        let api = try workspaceAPI
        let ids = try await pinned ? api.pinSession(sessionId: session.id) : api.unpinSession(sessionId: session.id)
        actions?.setPinnedSessions(ids)
    }
    func archive(_ session: SessionSummary, archived: Bool, stopActivity: Bool = false) async throws {
        let api = try workspaceAPI
        let ids = try await archived ? api.archiveSession(sessionId: session.id, stopActivity: stopActivity) : api.unarchiveSession(sessionId: session.id)
        actions?.setArchivedSessions(ids)
        if archived, ids.contains(session.id), context.currentSessionId == session.id { actions?.newChat() }
        await refreshSessions()
    }
    func rename(_ session: SessionSummary, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let client else { return }
        try? await client.renameSession(session.id, title: trimmed)
        await refreshSessions()
    }
    func delete(_ session: SessionSummary) async -> String? {
        guard let client else { return "E_TRANSPORT" }
        if session.id == context.currentSessionId { actions?.newChat() }
        do { try await client.deleteSession(session.id) }
        catch { await refreshSessions(); return appErrorCode(error) }
        sessions.removeAll { $0.id == session.id }
        return nil
    }
}

/// Shared values are readable through SessionContext; only this store file can write them.
@MainActor @Observable final class SessionListState {
    fileprivate(set) var sessions: [SessionSummary] = []
}
