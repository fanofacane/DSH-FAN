// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient

/// Cross-store commands only; state queries belong to SessionContext.
@MainActor protocol SessionActions: AnyObject {
    func newChat()
    func refreshSessions() async
    func setTranscriptLoading(_ value: Bool)
    func ensureSession() async throws -> String
    func appendNotice(_ code: String)
    func useNewChatDefault()
    func selectModel(_ model: ModelOption?)
    func didOpenSession(_ session: SessionSummary)
    func insertSession(_ session: SessionSummary)
    func setPinnedSessions(_ ids: [String])
    func setArchivedSessions(_ ids: [String])
}

@MainActor protocol ConnectionLifecycle: AnyObject {
    func closeSession()
    func resetRequests()
    func resetRunningSessions()
    func resetFeeds()
    func receiveHostRequest(_ request: HostRequest)
    func startFeeds(_ client: DSHClient, generation: Int) async
    func connectionReady() async
}

@MainActor protocol HostLinkEvents: AnyObject { func hostLinkLost() }

extension AppSession: SessionActions, ConnectionLifecycle {
    func newChat() { transcript.newChat() }
    func refreshSessions() async { await sessionList.refreshSessions() }
    func setTranscriptLoading(_ value: Bool) { transcript.setLoading(value) }
    func ensureSession() async throws -> String { try await transcript.ensureSession() }
    func appendNotice(_ code: String) { transcript.appendNotice(code) }
    func useNewChatDefault() { connection.useNewChatDefault() }
    func selectModel(_ model: ModelOption?) { connection.selectedModel = model }
    func didOpenSession(_ session: SessionSummary) { workspace.didOpen(session) }
    func insertSession(_ session: SessionSummary) { sessionList.insert(session) }
    func setPinnedSessions(_ ids: [String]) { workspace.setPinned(ids) }
    func setArchivedSessions(_ ids: [String]) { workspace.setArchived(ids) }
    func closeSession() { transcript.closeSession() }
    func resetRequests() { requests.reset() }
    func resetRunningSessions() { requests.resetRunning() }
    func resetFeeds() { control.resetFeed(); workspace.resetFeed(); schedule.reset() }
    func receiveHostRequest(_ request: HostRequest) { requests.receive(request) }
    func startFeeds(_ client: DSHClient, generation: Int) async {
        control.startControl(client, generation: generation)
        workspace.startWorkspaces(client, generation: generation)
        await control.loadPermissions(client)
    }
    func connectionReady() async { await transcript.drainIntents() }
}
