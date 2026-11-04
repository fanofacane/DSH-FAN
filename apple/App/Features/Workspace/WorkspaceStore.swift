// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import Foundation
import Observation

@MainActor @Observable final class WorkspaceStore {
    private let shared: WorkspaceSessionState
    var state: WorkspaceState {
        get { shared.state }
        set { shared.state = newValue }
    }
    var error: String?
    private(set) var selectedWorkspaceId: String? {
        get { shared.selectedWorkspaceId }
        set { shared.selectedWorkspaceId = newValue }
    }
    private(set) var selectedDirectory: String? {
        get { shared.selectedDirectory }
        set { shared.selectedDirectory = newValue }
    }
    private var workspaceTask: Task<Void, Never>?
    private let context: SessionContext
    private let hosts: any HostProviding
    @ObservationIgnored private weak var actions: (any SessionActions)?
    private var generation: Int { context.generation }
    private func api() throws -> WorkspaceAPI { WorkspaceAPI(client: try context.requireClient()) }
    private func files() throws -> FilesAPI { FilesAPI(client: try context.requireClient()) }
    init(context: SessionContext, actions: any SessionActions, hosts: any HostProviding) {
        self.context = context; shared = context.workspaceState; self.actions = actions; self.hosts = hosts
    }
    func setPinned(_ ids: [String]) { state.setPinned(ids) }
    func setArchived(_ ids: [String]) { state.setArchived(ids) }
    func resetFeed() { workspaceTask?.cancel(); workspaceTask = nil; state = WorkspaceState() }
    func clearSelection() { selectedWorkspaceId = nil; selectedDirectory = nil }
    var creationWorkspace: WorkspaceRecord? { state.items.first { $0.id == selectedWorkspaceId } }
    var workingDirectoryLabel: String {
        if let id = context.currentSessionId, let cwd = context.sessions.first(where: { $0.id == id })?.cwd { return cwd }
        return creationWorkspace?.path ?? selectedDirectory ?? hosts.sessionDirectory ?? String(localized: "Host default directory")
    }
    func didOpen(_ session: SessionSummary) { selectedWorkspaceId = state.items.first { $0.sessionIds.contains(session.id) }?.id; selectedDirectory = session.cwd }
    func chooseWorkspace(_ id: String?) {
        guard !context.busy else { return }
        actions?.newChat(); selectedWorkspaceId = id; selectedDirectory = nil
    }
    func chooseDirectory(_ path: String) {
        guard !context.busy else { return }
        actions?.newChat(); selectedWorkspaceId = nil; selectedDirectory = path
    }
    @discardableResult func registerWorkspace(_ path: String) async throws -> WorkspaceRecord { try await api().create(path: path) }
    func renameWorkspace(_ id: String, title: String) async throws {
        try await api().rename(workspaceId: id, title: title.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    func removeWorkspace(_ id: String) async throws {
        try await api().delete(workspaceId: id)
        if selectedWorkspaceId == id { selectedWorkspaceId = nil }
        await actions?.refreshSessions()
    }
    func startWorkspaces(_ client: DSHClient, generation: Int) {
        workspaceTask?.cancel(); state = WorkspaceState(); error = nil
        workspaceTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let frames = try await WorkspaceAPI(client: client).follow()
                    for try await frame in frames {
                        guard let self, !Task.isCancelled, self.generation == generation else { return }
                        self.state.apply(frame); self.error = nil
                    }
                } catch {
                    guard let self, !Task.isCancelled, self.generation == generation else { return }
                    self.error = appErrorCode(error)
                }
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            }
        }
    }
    func fileBytes(sessionId: String, path: String) async throws -> Data { try await files().readBytes(workspaceFileScopeId: sessionId, path: path) }
    func officePDF(sessionId: String, path: String) async throws -> Data { try await files().renderOfficePDF(workspaceFileScopeId: sessionId, path: path) }
}

/// Shared values are readable through SessionContext; only this store file can write them.
@MainActor @Observable final class WorkspaceSessionState {
    fileprivate(set) var state: WorkspaceState = WorkspaceState()
    fileprivate(set) var selectedWorkspaceId: String? = nil
    fileprivate(set) var selectedDirectory: String? = nil
}
