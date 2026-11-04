// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import Observation

/// Shared reads, backed by each store's sole mutable source. No state is mirrored.
/// Storage setters are fileprivate to the owning store, including under @testable import.
@MainActor @Observable final class SessionContext {
    let connectionState = ConnectionSessionState()
    let transcriptState = TranscriptSessionState()
    let sessionListState = SessionListState()
    let workspaceState = WorkspaceSessionState()
    let permissionState = PermissionSessionState()
    let agentState = AgentSessionState()
    let requestState = RequestSessionState()

    var connection: ConnectionState { connectionState.state }
    var models: [ModelOption] { connectionState.models }
    var selectedModel: ModelOption? { connectionState.selectedModel }
    var generation: Int { connectionState.generation }
    var client: DSHClient? { connectionState.client }
    var currentSessionId: String? { transcriptState.currentSessionId }
    var busy: Bool { transcriptState.turnRunning || transcriptState.sending }
    var hasRunningTasks: Bool { busy || !requestState.runningSessions.isEmpty }
    var sessions: [SessionSummary] { sessionListState.sessions }
    var permissionPreset: String? { permissionState.permissionPreset }
    var permissionPresets: [PermissionPreset] { permissionState.permissionPresets }
    var enginePermissionDefault: String { permissionState.enginePermissionDefault }
    var workspace: WorkspaceRecord? { workspaceState.state.items.first { $0.id == workspaceState.selectedWorkspaceId } }
    var directory: String? { workspaceState.selectedDirectory }
    var agentPreset: String? { agentState.selectedAgentPreset }

    func effort(for model: ModelOption?) -> String? {
        guard let model, !model.efforts.isEmpty else { return nil }
        return connectionState.efforts[model.id] ?? model.defaultEffort
    }
    func requireClient() throws -> DSHClient {
        guard let client else { throw DSHError("E_NOT_CONNECTED") }; return client
    }
}
