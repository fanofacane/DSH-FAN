// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
@testable import DSH
@testable import DSHClient

@MainActor final class FakeHosts: HostProviding {
    let client: DSHClient
    var selected: String?
    var attempts = 0
    var factory: (() async throws -> DSHClient)?
    init(_ client: DSHClient) { self.client = client }
    var activeHost: ActiveHost? { selected.map { ActiveHost(kind: .ssh, id: $0, name: $0, detail: $0) } }
    var isRemote: Bool { selected != nil }
    var sessionDirectory: String? { "/work" }
    func select(_ id: String?) { selected = id }
    func makeClient(forceRestart: Bool) async throws -> DSHClient {
        attempts += 1
        if let factory { return try await factory() }; return client
    }
}
@MainActor final class FakeNotifications: TaskNotifying {
    var ids: [String] = []
    var graceFinishes = 0
    func notify(_ kind: TaskNotifications.Kind, eventId: String, sessionId: String, hostId: String?) async -> Bool { ids.append(eventId); return false }
    func finishGrace() { graceFinishes += 1 }
}
@MainActor struct StoreRig {
    let fixture: APITransportFixture
    let hosts: FakeHosts
    let phone = FakePhone()
    let notifications = FakeNotifications()
    let app: AppSession
    init(extra: [String: Any] = [:], failures: [String: DSHError] = [:], onCall: (@Sendable (String) async -> Void)? = nil) {
        var responses: [String: Any] = [
            "credentials/describe": [DSHClient.deepSeekKeyRef: ["configured": true, "writable": true]],
            "session/modelCatalog": ["groups": [["id": "p", "models": [["id": "m", "name": "Model"]]]], "default": ["provider": "p", "model": "m"]],
            "session/list": ["items": [["sessionId": "s", "agentAvailable": true, "projections": ["values": ["title": "Session"]]]]],
            "permissionPresets/catalog": ["defaultPreset": "danger-full-access", "options": [["value": "danger-full-access"], ["value": "test-preset"]]],
            "session/create": ["sessionId": "s"], "commands/execute": ["result": ["kind": "success"]],
            "workspace/pinSession": ["pinnedSessionIds": ["s"]], "workspace/rename": [:],
            "agentPresets/select": [:], "schedule/catalog": [["id": "t", "sessionId": "s", "title": "Task"]],
            "goals/pause": [:]]
        responses.merge(extra) { _, next in next }
        let values: [String: Any] = ["todos": [["content": "one", "status": "pending"]],
            "goal": ["goal": ["id": "g", "revision": 1, "objective": "Goal", "phase": "active"]]]
        let control: [String: Any] = ["type": "baseline", "value": ["projections": ["s": ["asOfSeq": 1, "values": values]]]]
        let workspace: [String: Any] = ["type": "baseline", "value": ["items": [["workspaceId": "w", "title": "Work", "path": "/work", "sessionIds": ["s"]]]]]
        fixture = APITransportFixture(responses: responses, failures: failures, frames: [
            "session/control": [control], "workspace/follow": [workspace],
            "session/follow": [["type": "snapshot", "records": [], "hasMore": false]]], onCall: onCall)
        hosts = FakeHosts(DSHClient(carrier: fixture))
        app = AppSession(hosts: hosts, phone: phone, notifications: notifications, intents: IntentInbox())
    }
    func stop() { app.connection.disconnect() }
}
