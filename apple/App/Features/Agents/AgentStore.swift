// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import Foundation
import Observation

@MainActor @Observable final class AgentStore {
    private let shared: AgentSessionState
    private(set) var selectedAgentPreset: String? {
        get { shared.selectedAgentPreset }
        set { shared.selectedAgentPreset = newValue }
    }
    private let context: SessionContext
    @ObservationIgnored private weak var actions: (any SessionActions)?
    private var generation: Int { context.generation }
    private func api() throws -> AgentAPI { AgentAPI(client: try context.requireClient()) }
    init(context: SessionContext, actions: any SessionActions) {
        self.context = context; shared = context.agentState; self.actions = actions
    }
    func clearSelection() { selectedAgentPreset = nil }
    func chooseAgentPreset(_ id: String) async throws {
        guard !context.busy else { throw DSHError("E_SESSION_BUSY") }
        actions?.newChat()
        actions?.setTranscriptLoading(true)
        let previous = selectedAgentPreset, epoch = generation
        selectedAgentPreset = id
        defer { actions?.setTranscriptLoading(false) }
        do {
            guard let actions else { throw DSHError("E_NOT_CONNECTED") }
            let session = try await actions.ensureSession()
            try await api().select(agentId: session, agentPreset: id)
            guard epoch == generation else { throw DSHError("E_STALE_CONNECTION") }
        } catch {
            if epoch == generation { selectedAgentPreset = previous }
            throw error
        }
    }
    func childEvents(_ route: SubagentRoute) async throws -> AsyncThrowingStream<ChatEvent, Error> { try await api().follow(route) }
    func promptChild(_ route: SubagentRoute, text: String) async throws {
        guard route.canPrompt else { throw DSHError("E_SUBAGENT_READ_ONLY") }
        try await api().prompt(route, text: text)
    }
    func interruptChild(_ route: SubagentRoute) async throws {
        guard route.canPrompt else { throw DSHError("E_SUBAGENT_READ_ONLY") }
        try await api().interruptByParent(route)
    }
}

/// Shared values are readable through SessionContext; only this store file can write them.
@MainActor @Observable final class AgentSessionState {
    fileprivate(set) var selectedAgentPreset: String? = nil
}
