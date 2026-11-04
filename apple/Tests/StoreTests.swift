// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing
@testable import DSH
@testable import DSHClient

@MainActor struct StoreTests {
    @Test func connectionUsesFakeHostClient() async {
        let rig = StoreRig(); defer { rig.stop() }
        await rig.app.connection.connect()
        #expect(rig.app.connection.state == .ready && rig.hosts.attempts == 1)
        #expect(rig.app.connection.selectedModel?.id == "p/m" && rig.app.connection.keyConfigured)
        #expect(rig.phone.connectionChanges == 1)
    }
    @Test func transcriptAdoptsCreatedSessionAfterPermissionFailure() async throws {
        let rig = StoreRig(failures: ["commands/execute": DSHError("E_TEST_PRESET")]); defer { rig.stop() }
        let previous = rig.app.control.permissionPreset
        defer { rig.app.control.permissionPreset = previous }
        rig.app.control.permissionPreset = "test-preset"
        await rig.app.connection.connect()
        let first = try await rig.app.transcript.ensureSession()
        let second = try await rig.app.transcript.ensureSession()
        #expect(first == "s" && second == first)
        #expect(rig.fixture.calls.filter { $0.endpoint == "session/create" }.count == 1)
        #expect(rig.app.transcript.currentSessionId == first)
        // The snapshot replaces the log; the permission notice must survive it.
        #expect(rig.app.transcript.items.contains { $0.role == .notice && $0.state == .failed("E_TEST_PRESET") })
    }
    @Test func transcriptReadsLatestPermissionAfterCreateReturns() async throws {
        let box = WeakSessionBox()
        let rig = StoreRig(onCall: { endpoint in
            if endpoint == "session/create" {
                await MainActor.run { box.app?.control.permissionPreset = ControlStore.iosDefaultPreset }
            }
        })
        box.app = rig.app
        defer { rig.stop() }
        let previous = rig.app.control.permissionPreset
        defer { rig.app.control.permissionPreset = previous }
        await rig.app.connection.connect()
        rig.app.control.permissionPreset = "test-preset"
        _ = try await rig.app.transcript.ensureSession()
        #expect(rig.app.control.permissionPreset == ControlStore.iosDefaultPreset)
        #expect(!rig.fixture.calls.contains { $0.endpoint == "commands/execute" })
    }
    @Test func sessionListMutatesPinThroughTypedAPI() async throws {
        let rig = StoreRig(); defer { rig.stop() }
        await rig.app.connection.connect()
        let summary = try #require(rig.app.sessionList.sessions.first)
        try await rig.app.sessionList.pin(summary, pinned: true)
        #expect(rig.app.workspace.state.pinned == ["s"])
        #expect(rig.fixture.calls.contains { $0.endpoint == "workspace/pinSession" })
    }
    @Test func workspaceOwnsSelectionAndProjection() async {
        let rig = StoreRig(); defer { rig.stop() }
        await rig.app.connection.connect()
        for _ in 0..<100 where rig.app.workspace.state.items.isEmpty { await Task.yield() }
        #expect(rig.app.workspace.state.items.first?.id == "w")
        rig.app.workspace.chooseWorkspace("w")
        #expect(rig.app.workspace.creationWorkspace?.path == "/work")
        rig.app.workspace.chooseDirectory("/other")
        #expect(rig.app.workspace.selectedWorkspaceId == nil && rig.app.workspace.selectedDirectory == "/other")
    }
    @Test func scheduleStoreLoadsFakeCatalog() async throws {
        let rig = StoreRig(); defer { rig.stop() }
        await rig.app.connection.connect()
        let entries = try await rig.app.schedule.schedules()
        #expect(entries.first?.taskId == "t" && rig.app.schedule.entries.first?.title == "Task")
    }
    @Test func agentStoreSelectsPresetOnCreatedSession() async throws {
        let rig = StoreRig(); defer { rig.stop() }
        await rig.app.connection.connect()
        try await rig.app.agents.chooseAgentPreset("preset")
        #expect(rig.app.agents.selectedAgentPreset == "preset" && !rig.app.transcript.loadingSession)
        let call = try #require(rig.fixture.calls.first { $0.endpoint == "agentPresets/select" })
        #expect(call.args["agentId"] as? String == "s" && call.args["agentPreset"] as? String == "preset")
    }
    @Test func controlStoreFoldsProjectionAndUsesRevision() async throws {
        let rig = StoreRig(); defer { rig.stop() }
        await rig.app.connection.connect()
        _ = try await rig.app.transcript.ensureSession()
        for _ in 0..<100 where rig.app.control.projection.goal == nil { await Task.yield() }
        let goal = try #require(rig.app.control.projection.goal)
        #expect(rig.app.control.projection.todos.first?.content == "one")
        try await rig.app.control.changeGoal(.pause, goal: goal)
        let call = try #require(rig.fixture.calls.last { $0.endpoint == "goals/pause" })
        #expect((call.args["ref"] as? [String: Any])?["revision"] as? Int == 1)
    }
    @Test func hostRequestStoreReceivesDeduplicatedFakeEvents() async throws {
        let rig = StoreRig(); defer { rig.stop() }
        await rig.app.connection.connect()
        let event: [String: Any] = ["type": "waterfall", "eventId": "approval", "agentId": "s", "event": "approval/request", "request": ["toolName": "bash"]]
        rig.fixture.emitEvent(event); rig.fixture.emitEvent(event)
        for _ in 0..<100 where rig.app.requests.approvals.isEmpty { await Task.yield() }
        #expect(rig.app.requests.approvals.count == 1)
        rig.app.requests.receive(.sessionStatus(sessionId: "s", running: true))
        #expect(rig.phone.sessionStates["s"] == true && rig.app.hasRunningTasks)
        rig.app.requests.receive(.cancelled(eventId: "approval"))
        #expect(rig.app.requests.approvals.isEmpty)
    }
    @Test func switchingHostResetsStoresTogether() async throws {
        let rig = StoreRig(); defer { rig.stop() }
        await rig.app.connection.connect()
        _ = try await rig.app.transcript.ensureSession()
        _ = try await rig.app.schedule.schedules()
        rig.app.workspace.chooseDirectory("/other")
        await rig.app.switchHost(to: nil, engineRunning: false)
        #expect(rig.app.connection.state == .idle && rig.app.connection.models.isEmpty)
        #expect(rig.app.transcript.currentSessionId == nil && rig.app.transcript.items.isEmpty)
        #expect(rig.app.sessionList.sessions.isEmpty && rig.app.workspace.state.items.isEmpty)
        #expect(rig.app.workspace.selectedDirectory == nil && rig.app.schedule.entries.isEmpty)
        #expect(rig.app.control.state.values.isEmpty && !rig.app.hasRunningTasks)
    }
    @Test func lateConnectionDoesNotSurviveDisconnect() async throws {
        let rig = StoreRig(); defer { rig.stop() }
        var waiter: CheckedContinuation<DSHClient, Never>?
        rig.hosts.factory = { await withCheckedContinuation { waiter = $0 } }
        let connect = Task { await rig.app.connection.connect() }
        for _ in 0..<100 where waiter == nil { await Task.yield() }
        let pending = try #require(waiter)
        rig.app.connection.disconnect()
        pending.resume(returning: rig.hosts.client)
        await connect.value
        #expect(rig.app.connection.state == .idle && rig.app.connection.client == nil)
        #expect(rig.fixture.closeCount > 0)
    }
}

@MainActor private final class WeakSessionBox { weak var app: AppSession? }
