// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import Foundation
import Observation

@MainActor @Observable final class ConnectionStore {
    private let shared: ConnectionSessionState
    private(set) var state: ConnectionState {
        get { shared.state }
        set { shared.state = newValue }
    }
    private(set) var keyConfigured = false
    private(set) var keyWritable = true
    private(set) var keyError: String?
    private(set) var newChatDefault: ModelOption?
    private var newChatDefaultRevision: Int?
    private(set) var models: [ModelOption] {
        get { shared.models }
        set { shared.models = newValue }
    }
    var selectedModel: ModelOption? {
        get { shared.selectedModel }
        set { shared.selectedModel = newValue }
    }
    private(set) var efforts: [String: String] {
        get { shared.efforts }
        set { shared.efforts = newValue }
    }
    private(set) var generation: Int {
        get { shared.generation }
        set { shared.generation = newValue }
    }
    private(set) var client: DSHClient? {
        get { shared.client }
        set { shared.client = newValue }
    }
    private let hosts: any HostProviding
    private let phone: any PhoneControlling
    private let prefs = UserDefaults.standard
    private let context: SessionContext
    // Required at initialization; weak storage preserves teardown without a retain cycle.
    @ObservationIgnored private weak var actions: (any SessionActions & ConnectionLifecycle)?
    init(context: SessionContext, actions: any SessionActions & ConnectionLifecycle, hosts: any HostProviding, phone: any PhoneControlling) {
        self.context = context; shared = context.connectionState; self.actions = actions
        self.hosts = hosts; self.phone = phone
        efforts = prefs.dictionary(forKey: "chat.efforts") as? [String: String] ?? [:]
    }
    func resetCatalog() { models = []; selectedModel = nil; keyConfigured = false }
    func connect(forceRestart: Bool = false) async {
        guard state != .connecting else { return }
        state = .connecting
        newChatDefault = nil; newChatDefaultRevision = nil
        generation += 1
        let generation = generation
        actions?.closeSession()
        client?.close(); client = nil
        actions?.resetRequests()
        do {
            // This phone's engine, an SSH host, or a DSH Remote Host.
            let fresh = try await self.hosts.makeClient(forceRestart: forceRestart)
            guard generation == self.generation else { fresh.close(); return }
            client = fresh
            self.phone.hostConnectionChanged()
            fresh.setHostRequestHandler { [weak self] request in
                Task { @MainActor in
                    guard let self, self.generation == generation else { return }
                    self.actions?.receiveHostRequest(request)
                }
            }
            // Open the mux now so approvals pending from earlier are redelivered.
            _ = try await fresh.muxConnection()
            await actions?.startFeeds(fresh, generation: generation)
            try await reloadModels()
            await actions?.refreshSessions()
            guard generation == self.generation else { return }
            state = .ready
            Task { await actions?.connectionReady() }
            Task {
                // Older Hosts may not expose these settings. The catalog still supplies the legacy default.
                let settings = try? await SettingsAPI(client: fresh).describe()
                guard generation == self.generation else { return }
                if let section = settings?.first(where: { $0.id == "agent-default-model" }) {
                    updateNewChatDefault(from: section)
                }
            }
        } catch {
            guard generation == self.generation else { return }
            if let failure = error as? LinkFailure { state = .failed(failure.code) } else { state = .failed(appErrorCode(error)) }
        }
    }
    func disconnect() {
        generation += 1
        newChatDefault = nil; newChatDefaultRevision = nil
        actions?.resetFeeds()
        self.phone.hostConnectionChanged()
        actions?.closeSession()
        client?.close(); client = nil
        state = .idle; actions?.resetRunningSessions()
    }
    func linkLost() {
        generation += 1
        newChatDefault = nil; newChatDefaultRevision = nil
        actions?.resetFeeds()
        actions?.closeSession()
        client?.close(); client = nil
        state = .failed("E_LINK_LOST"); actions?.resetRunningSessions()
    }
    func effort(for model: ModelOption?) -> String? {
        context.effort(for: model)
    }
    func setEffort(_ effort: String, for model: ModelOption) {
        efforts[model.id] = effort
        prefs.set(efforts, forKey: "chat.efforts")
    }
    func saveKey(_ key: String) async -> Bool {
        guard let client else { return false }
        keyError = nil
        do {
            try await client.setProviderKey(key)
            keyConfigured = true
            try await reloadModels()
            return true
        } catch {
            keyError = appErrorCode(error)
            return false
        }
    }
    func reloadModels() async throws {
        guard let client else { return }
        let state = try await client.credentialState()
        keyConfigured = state.configured; keyWritable = state.writable
        let catalog = try await client.modelCatalog()
        models = catalog.models
        if selectedModel == nil || !models.contains(selectedModel!) {
            selectedModel = catalog.defaultModel.flatMap { d in models.first { $0 == d } } ?? models.first
        }
    }
    func clearKey() async {
        guard let client else { return }
        try? await client.clearProviderKey()
        actions?.newChat()
        keyConfigured = (try? await client.credentialState().configured) ?? false
        try? await reloadModels()
    }
    func updateNewChatDefault(from section: EngineNamespace) {
        guard newChatDefaultRevision.map({ section.revision >= $0 }) ?? true else { return }
        newChatDefaultRevision = section.revision
        newChatDefault = nil
        guard section.value["rememberLastSelection"] as? Bool == false,
              let provider = section.value["provider"] as? String, let modelID = section.value["model"] as? String,
              var model = models.first(where: { $0.provider == provider && $0.model == modelID }) else { return }
        if let effort = section.value["reasoningEffort"] as? String, model.efforts.contains(where: { $0.id == effort }) {
            model.defaultEffort = effort
        }
        newChatDefault = model
    }
    func useNewChatDefault() {
        if let newChatDefault, models.contains(newChatDefault) { selectedModel = newChatDefault }
    }
    func requireClient() throws -> DSHClient {
        guard let client else { throw DSHError("E_NOT_CONNECTED") }; return client
    }
    var controlAPI: ControlAPI { get throws { ControlAPI(client: try requireClient()) } }
    var workspaceAPI: WorkspaceAPI { get throws { WorkspaceAPI(client: try requireClient()) } }
    var scheduleAPI: ScheduleAPI { get throws { ScheduleAPI(client: try requireClient()) } }
    var agentAPI: AgentAPI { get throws { AgentAPI(client: try requireClient()) } }
    var providerAPI: ProviderAPI { get throws { ProviderAPI(client: try requireClient()) } }
    var settingsAPI: SettingsAPI { get throws { SettingsAPI(client: try requireClient()) } }
    var filesAPI: FilesAPI { get throws { FilesAPI(client: try requireClient()) } }
    var commandsAPI: CommandsAPI { get throws { CommandsAPI(client: try requireClient()) } }
    var credentialsAPI: CredentialsAPI { get throws { CredentialsAPI(client: try requireClient()) } }
    var accountAPI: AccountAPI {
        get throws {
            guard !hosts.isRemote else { throw DSHError("E_ACCOUNT_LOCAL_ONLY") }
            return AccountAPI(client: try requireClient(), isLocal: true)
        }
    }
    #if DEBUG
    var complianceAPI: StoreComplianceAPI { get throws { StoreComplianceAPI(client: try requireClient()) } }
    #endif

}

/// Shared values are readable through SessionContext; only this store file can write them.
@MainActor @Observable final class ConnectionSessionState {
    fileprivate(set) var state: ConnectionState = .idle
    fileprivate(set) var models: [ModelOption] = []
    fileprivate(set) var selectedModel: ModelOption? = nil
    fileprivate(set) var efforts: [String: String] = [:]
    fileprivate(set) var generation: Int = 0
    fileprivate(set) var client: DSHClient? = nil
}
