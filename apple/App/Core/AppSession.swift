// SPDX-License-Identifier: AGPL-3.0-or-later
import Observation

/// Composition and host-wide resets only; feature state and business actions live in stores.
@MainActor @Observable final class AppSession {
    let context = SessionContext()
    // Lazy construction lets every store receive the fully initialized actions owner.
    // All stores are realized below before the session escapes its initializer.
    @ObservationIgnored private(set) lazy var connection = ConnectionStore(context: context, actions: self, hosts: hosts, phone: phone)
    @ObservationIgnored private(set) lazy var transcript = TranscriptStore(context: context, actions: self, hosts: hosts, notifications: notifications, intents: intents)
    @ObservationIgnored private(set) lazy var sessionList = SessionListStore(context: context, actions: self)
    @ObservationIgnored private(set) lazy var workspace = WorkspaceStore(context: context, actions: self, hosts: hosts)
    @ObservationIgnored private(set) lazy var schedule = ScheduleStore(context: context)
    @ObservationIgnored private(set) lazy var agents = AgentStore(context: context, actions: self)
    @ObservationIgnored private(set) lazy var control = ControlStore(context: context)
    @ObservationIgnored private(set) lazy var requests = HostRequestStore(context: context, actions: self, hosts: hosts, phone: phone, notifications: notifications)
    private let hosts: any HostProviding
    private let phone: any PhoneControlling
    private let notifications: any TaskNotifying
    private let intents: IntentInbox
    #if DEBUG
    var runCapturePanel: RunPanelRoute?
    #endif
    var hasRunningTasks: Bool { context.hasRunningTasks }

    init(hosts: any HostProviding, phone: any PhoneControlling, notifications: any TaskNotifying, intents: IntentInbox) {
        self.hosts = hosts; self.phone = phone; self.notifications = notifications; self.intents = intents
        _ = (connection, transcript, sessionList, workspace, schedule, agents, control, requests)
    }
    func switchHost(to id: String?, engineRunning: Bool) async {
        hosts.select(id)
        connection.disconnect()
        connection.resetCatalog(); sessionList.reset()
        workspace.clearSelection(); agents.clearSelection()
        transcript.newChat()
        if hosts.isRemote || engineRunning { await connection.connect() }
    }
}
