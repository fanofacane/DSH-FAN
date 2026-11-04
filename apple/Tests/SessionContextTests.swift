// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Observation
import Testing
@testable import DSH
@testable import DSHClient

@MainActor struct SessionContextTests {
    @Test func contextExposesReadOnlyState() {
        // These key paths are formed outside the owner's source file, just like a reader Store.
        // Adding `context.busy = true` or `context.connectionState.models = []` fails to compile.
        readOnly(\SessionContext.connection)
        readOnly(\SessionContext.currentSessionId)
        readOnly(\SessionContext.busy)
        readOnly(\SessionContext.hasRunningTasks)
        readOnly(\SessionContext.models)
        readOnly(\SessionContext.selectedModel)
        readOnly(\SessionContext.generation)
        readOnly(\SessionContext.client)
        readOnly(\SessionContext.sessions)
        readOnly(\SessionContext.permissionPreset)
        readOnly(\SessionContext.permissionPresets)
        readOnly(\SessionContext.enginePermissionDefault)
        readOnly(\SessionContext.workspace)
        readOnly(\SessionContext.directory)
        readOnly(\SessionContext.agentPreset)
        // Underlying storage setters are fileprivate to their owning store files.

    }

    @Test func ownersPublishWithoutMirroringOrOverwritingOtherOwners() async throws {
        let rig = StoreRig(); defer { rig.stop() }
        let context = rig.app.context
        await rig.app.connection.connect()
        #expect(context.connection == .ready && context.selectedModel?.id == "p/m")
        #expect(context.models == rig.app.connection.models && context.client === rig.app.connection.client)
        #expect(context.sessions.map(\.id) == ["s"])
        #expect(context.permissionPreset == rig.app.control.permissionPreset)
        #expect(context.permissionPresets == rig.app.control.permissionPresets)
        #expect(context.enginePermissionDefault == rig.app.control.enginePermissionDefault)
        for _ in 0..<100 where rig.app.workspace.state.items.isEmpty { await Task.yield() }
        rig.app.workspace.chooseDirectory("/context-test")
        #expect(context.directory == "/context-test" && context.currentSessionId == nil)
        rig.app.workspace.chooseWorkspace("w")
        #expect(context.workspace?.id == "w" && context.directory == nil)
        try await rig.app.agents.chooseAgentPreset("preset")
        #expect(context.agentPreset == "preset" && context.currentSessionId == "s")
        rig.app.sessionList.reset()
        #expect(context.sessions.isEmpty && context.currentSessionId == "s")
        rig.app.transcript.turnRunning = true
        #expect(context.busy && context.hasRunningTasks)
        rig.app.requests.receive(.sessionStatus(sessionId: "other", running: true))
        rig.app.transcript.closeSession()
        #expect(context.currentSessionId == nil && !context.busy && context.hasRunningTasks)
        rig.app.requests.resetRunning()
        #expect(!context.hasRunningTasks && context.agentPreset == "preset")
        let generation = context.generation
        rig.app.connection.disconnect()
        #expect(context.generation == generation + 1 && context.client == nil)
    }

    @Test func contextReadsParticipateInObservation() {
        let rig = StoreRig(); defer { rig.stop() }
        let changed = ChangeFlag()
        withObservationTracking { _ = rig.app.context.busy } onChange: { changed.set() }
        rig.app.transcript.turnRunning = true
        #expect(changed.value)
        // Missing dependencies cannot silently construct an inert store:
        // SessionListStore() and SessionListStore(context: rig.app.context) do not compile.
    }
}

private func readOnly<Root, Value>(_ keyPath: KeyPath<Root, Value>) {
    let erased: AnyKeyPath = keyPath
    #expect(!(erased is ReferenceWritableKeyPath<Root, Value>))
}

// Observation's onChange is Sendable; keep the test notification synchronized.
private final class ChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return changed }
    func set() { lock.lock(); defer { lock.unlock() }; changed = true }
}
