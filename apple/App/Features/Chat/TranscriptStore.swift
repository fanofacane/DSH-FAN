// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import Foundation
import Observation

@MainActor @Observable final class TranscriptStore {
    private let shared: TranscriptSessionState
    // Implementation is split across extensions; mutations are performed by store actions.
    var currentSessionId: String? {
        get { shared.currentSessionId }
        set { shared.currentSessionId = newValue }
    }
    var items: [ChatItem] { committed + pending + (draft.map { [$0] } ?? []) }
    var runFacts: [RunFact] = []
    var traceFold = TurnTraceFold()
    var turnTraces: [TurnTrace] { traceFold.turns }
    var historyHasMore = false
    var turnRunning: Bool {
        get { shared.turnRunning }
        set { shared.turnRunning = newValue }
    }
    var retrying: (retry: Int, max: Int?, code: String)?
    var incomingDraft: SharedDraft?
    var composerInsertion: String?
    var focusRequest = 0
    var loadingSession = false
    var committed: [ChatItem] = []
    var pending: [ChatItem] = []
    var draft: ChatItem?
    var lastSeq = -1
    var events: [LogEvent] = []
    var lastFailure: String?
    var sending: Bool {
        get { shared.sending }
        set { shared.sending = newValue }
    }
    var sessionModel: ModelOption?
    var sessionEffort: String?
    var sessionCreation: Task<String, Error>?
    var sessionEpoch = 0
    var followTask: Task<Void, Never>?
    var snapshotWaiter: CheckedContinuation<Void, Never>?
    var followReady = false
    let context: SessionContext
    @ObservationIgnored private(set) weak var actions: (any SessionActions)?
    var client: DSHClient? { context.client }
    let hosts: any HostProviding
    let notifications: any TaskNotifying
    let intents: IntentInbox
    @ObservationIgnored private var intentTask: Task<Void, Never>?
    init(context: SessionContext, actions: any SessionActions, hosts: any HostProviding, notifications: any TaskNotifying, intents: IntentInbox) {
        self.context = context; shared = context.transcriptState; self.actions = actions
        self.hosts = hosts; self.notifications = notifications; self.intents = intents
        let submissions = intents.submissions()
        intentTask = Task { [weak self] in
            for await _ in submissions { await self?.drainIntents() }
        }
    }
    deinit { intentTask?.cancel() }
    var selectedModel: ModelOption? {
        get { context.selectedModel }
        set { actions?.selectModel(newValue) }
    }
    var models: [ModelOption] { context.models }
    var sessions: [SessionSummary] { context.sessions }
    var busy: Bool { turnRunning || sending }
    var canSend: Bool { context.connection == .ready && selectedModel != nil && !busy && !loadingSession }
    var currentTitle: String? { sessions.first { $0.id == currentSessionId }?.title }
    func setLoading(_ value: Bool) { loadingSession = value }
    func requestComposerFocus() { focusRequest += 1 }
    func drainIntents() async {
        while canSend, let prompt = self.intents.take() {
            newChat()
            await send(prompt)
            while busy { try? await Task.sleep(nanoseconds: 300_000_000) }
        }
    }
    func newChat() {
        closeSession()
        committed = []; pending = []; draft = nil
        actions?.useNewChatDefault()
    }
    func open(_ session: SessionSummary) async {
        guard let client, session.id != currentSessionId else { return }
        newChat()
        currentSessionId = session.id
        actions?.didOpenSession(session)
        loadingSession = true
        defer { loadingSession = false }
        do {
            if !session.agentAvailable { _ = try await client.createSession(resume: session.id) }
            if let chosen = try? await client.sessionModel(session.id) {
                let match = models.first { $0.provider == chosen.provider && $0.model == chosen.model }
                sessionModel = match
                if let match { selectedModel = match }
            }
            startFollow(session.id)
            await waitForSnapshot()
        } catch {
            appendNotice(appErrorCode(error))
        }
    }
    func send(_ raw: String, images: [PromptImage] = []) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || !images.isEmpty), canSend, let client, let model = selectedModel else { return }
        sending = true
        defer { sending = false }
        lastFailure = nil
        let requestId = UUID().uuidString
        pending.append(ChatItem(id: "pending-" + requestId, role: .user, text: text,
                                imageCount: images.count, state: .pending, requestId: requestId))
        do {
            let sessionId = try await ensureSession()
            let effort = context.effort(for: model)
            if sessionModel != model || sessionEffort != effort {
                try await client.selectModel(sessionId: sessionId, model: model, reasoningEffort: effort)
                sessionModel = model; sessionEffort = effort
            }
            await waitForSnapshot()
            turnRunning = true
            try await client.prompt(sessionId: sessionId, text: text, images: images, requestId: requestId)
        } catch {
            turnRunning = false
            pending.removeAll { $0.requestId == requestId }
            appendNotice(appErrorCode(error))
        }
    }
    func ensureSession() async throws -> String {
        if let currentSessionId { return currentSessionId }
        guard let client else { throw DSHError("E_NOT_CONNECTED") }
        if let sessionCreation { return try await sessionCreation.value }
        let epoch = sessionEpoch
        let creating = Task { @MainActor in
            let context = self.context
            let workspace = context.workspace
            let directory = context.directory ?? self.hosts.sessionDirectory
            let id = try await client.createSession(cwd: workspace == nil ? directory : nil, workspaceId: workspace?.id, agentPreset: context.agentPreset)
            try Task.checkCancellation()
            // Match the original timing: preferences may change while create is awaiting the host.
            let permissions = self.context
            var permissionError: String?
            if let preset = permissions.permissionPreset, preset != permissions.enginePermissionDefault,
               permissions.permissionPresets.isEmpty || permissions.permissionPresets.contains(where: { $0.id == preset }) {
                do { try await client.setPermissionPreset(sessionId: id, preset: preset) }
                catch { permissionError = appErrorCode(error) }
            }
            try Task.checkCancellation()
            guard epoch == self.sessionEpoch else { throw CancellationError() }
            self.currentSessionId = id
            self.startFollow(id)
            if let permissionError {
                // Keep the created session even when its permission update fails.
                // Show the notice after the initial snapshot, which replaces items.
                await self.waitForSnapshot()
                guard epoch == self.sessionEpoch else { throw CancellationError() }
                self.appendNotice(permissionError)
            }
            return id
        }
        sessionCreation = creating
        defer { if epoch == sessionEpoch { sessionCreation = nil } }
        return try await creating.value
    }
}

/// Shared values are readable through SessionContext; only this store file can write them.
@MainActor @Observable final class TranscriptSessionState {
    fileprivate(set) var currentSessionId: String? = nil
    fileprivate(set) var turnRunning: Bool = false
    fileprivate(set) var sending: Bool = false
}
