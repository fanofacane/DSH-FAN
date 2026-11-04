// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing
@testable import DSHClient

struct DomainAPITests {
    @Test func workspaceRecordsAndRequests() async throws {
        let fixture = APITransportFixture(responses: [
            "workspace/create": ["workspace": ["workspaceId": "w", "title": "Work", "path": "/work", "sessionIds": ["s"]]],
            "directoryPicker/list": ["path": "/work", "crumbs": [["name": "root", "path": "/"]], "entries": [["name": "a", "path": "/work/a"]], "truncated": true],
            "workspace/pinSession": ["pinnedSessionIds": ["s"]], "workspace/archiveSession": ["archivedSessionIds": ["s"]]])
        let client = DSHClient(carrier: fixture); defer { client.close() }
        let api = WorkspaceAPI(client: client)
        let record = try await api.create(path: "/work")
        #expect(record.id == "w" && record.title == "Work" && record.sessionIds == ["s"])
        let directory = try await api.listDirectory(path: "/work")
        #expect(directory.path == "/work" && directory.crumbs.first?.path == "/" && directory.entries.first?.name == "a" && directory.truncated)
        #expect(try await api.pinSession(sessionId: "s") == ["s"])
        #expect(try await api.archiveSession(sessionId: "s", stopActivity: true) == ["s"])
        let request = fixture.calls.last?.args["request"] as? [String: Any]
        #expect(request?["stopActivity"] as? Bool == true)
    }
    @Test func scheduleSnapshotAndHistory() async throws {
        let task: [String: Any] = ["id": "t", "sessionId": "s", "prompt": "old", "kind": "at", "status": "active", "unknownFutureField": 7, "lastDelivery": [:]]
        let fixture = APITransportFixture(responses: ["schedule/catalog": [task],
            "schedule/update": ["record": ["id": "t", "prompt": "new", "title": "Edited", "kind": "every", "everySeconds": 3600]],
            "schedule/history": ["records": [["deliveredAt": "2026-11-04T00:00:00Z", "prompt": "sent"]], "nextBefore": "cursor", "earlierRecordsPruned": true],
            "schedule/delete": ["deleted": false]])
        let client = DSHClient(carrier: fixture); defer { client.close() }
        let api = ScheduleAPI(client: client), original = try #require(try await api.catalog().first)
        let updated = try await api.update(original, title: "Edited", prompt: "new", change: .every(seconds: 3600))
        #expect(updated.sessionId == "s" && updated.active && updated.everySeconds == 3600)
        let request = fixture.calls.last?.args["request"] as? [String: Any]
        let expected = request?["expected"] as? [String: Any]
        #expect(expected?["unknownFutureField"] as? Int == 7)
        #expect(expected?["sessionId"] == nil && expected?["status"] == nil && expected?["lastDelivery"] == nil)
        #expect((request?["change"] as? [String: Any])?["every_seconds"] as? Int == 3600)
        let history = try await api.history(sessionId: "s", id: "t", before: "old")
        #expect(history.records?.first?.prompt == "sent" && history.records?.first?.deliveredAt != nil)
        #expect(history.nextBefore == "cursor" && history.earlierRecordsPruned)
        // Preserve the host's false result; don't invent a successful deletion.
        #expect(try await api.delete(updated) == false)
    }
    @Test func agentCatalogDocumentAndReadOnlyRoute() async throws {
        let fixture = APITransportFixture(responses: ["agentPresets/list": ["presets": [["id": "p", "name": "Preset", "isDefault": true, "broken": NSNull()]]], "agentPresets/read": ["content": "name: Preset"]])
        let client = DSHClient(carrier: fixture); defer { client.close() }
        let api = AgentAPI(client: client), preset = try #require(try await api.list().first)
        #expect(preset.id == "p" && preset.isDefault && preset.hasBrokenField && preset.broken == nil)
        #expect(try await api.read(agentPreset: "p").content == "name: Preset")
        let route = try #require(SubagentRoute(["id": "child", "mode": "external"], parent: "parent"))
        do { try await api.prompt(route, text: "not sent"); Issue.record("Read-only child accepted prompt") }
        catch let error as DSHError { #expect(error.code == "E_SUBAGENT_READ_ONLY") }
        #expect(fixture.calls.count == 2)
    }
    @Test func providersAndCredentialState() async throws {
        let fixture = APITransportFixture(responses: [
            "llm/listConfigurableProviders": [["provider": "p", "displayName": "Provider", "settingsNs": "ns", "settingsPath": ["providers", "p"], "declared": true]],
            "llm/listProviders": [["id": "registered", "name": "Registered"]],
            "llm/discoverModels": [["id": "m", "inputModalities": ["text", "image"], "contextWindow": 4096]],
            "credentials/describe": ["REF": ["configured": true, "writable": false]]])
        let client = DSHClient(carrier: fixture); defer { client.close() }
        let api = ProviderAPI(client: client)
        let provider = try #require(try await api.listConfigurableProviders().first)
        #expect(provider.provider == "p" && provider.settingsPath == ["providers", "p"] && provider.declared)
        #expect(try await api.listProviders().first?.id == "registered")
        let model = try #require(try await api.discoverModels(settingsNs: "ns", request: ModelDiscoveryRequest(baseURL: "http://example.invalid/v1", api: "openai-completions")).first)
        #expect(model.id == "m" && model.settingsSpec["input"] as? [String] == ["text", "image"])
        #expect(model.settingsSpec["contextWindow"] as? Int == 4096)
        let states = try await CredentialsAPI(client: client).describe(refs: ["REF"])
        #expect(states["REF"]?.configured == true && states["REF"]?.writable == false)
    }
    @Test func accountSafeFieldsBalanceAndLocalGate() async throws {
        let fixture = APITransportFixture(responses: [
            "account/getState": ["status": "signed-out", "attempt": ["id": "a", "phase": "waiting-browser", "authorizeUrl": "https://platform.deepseek.com/authorize"]],
            "account/getProfile": ["status": "ready", "value": ["name": "Test", "contact": "test@example.invalid"]],
            "account/getBalance": ["status": "ready", "value": [["balance": "1.25", "currency": "USD"]], "bonusWallets": [["balance": "0.25", "currency": "USD"]]]])
        let client = DSHClient(carrier: fixture); defer { client.close() }
        let api = AccountAPI(client: client, isLocal: true)
        let state = try await api.getState()
        #expect(state.status == "signed-out" && state.attempt.id == "a" && state.attempt.phase == "waiting-browser")
        let info = AccountClientInfo(version: "test", locale: "en", timezoneOffsetSeconds: 0)
        #expect(try await api.getProfile(client: info).contact == "test@example.invalid")
        let wallets = try await api.getBalance(client: info)
        #expect(wallets.map(\.balance) == ["1.25", "0.25"] && !wallets[0].bonus && wallets[1].bonus)
        // An SSH client has no carrier; it must still reject the local-only account API.
        let ssh = DSHClient(baseURL: URL(string: "http://127.0.0.1:1")!); defer { ssh.close() }
        do { _ = try await AccountAPI(client: ssh, isLocal: false).getState(); Issue.record("Remote account call accepted") }
        catch let error as DSHError { #expect(error.code == "E_ACCOUNT_LOCAL_ONLY") }
    }
    @Test func settingsPreserveDynamicSchemaFields() async throws {
        let row: [String: Any] = ["ns": "ns", "revision": 5, "value": ["unknown": ["nested": 7]], "schema": ["uid": "root"], "secrets": [["set": true, "path": ["key"]]]]
        let fixture = APITransportFixture(responses: ["settings/describe": ["writable": false, "namespaces": [row]], "settings/mutate": row])
        let client = DSHClient(carrier: fixture); defer { client.close() }
        let api = SettingsAPI(client: client), section = try #require(try await api.describe().first)
        #expect(!section.writable && section.secretPaths == [["key"]])
        let saved = try await api.mutate(ns: "ns", expectedRevision: 4, ops: [["op": "set", "path": ["unknown", "nested"], "value": 7]], writable: false)
        #expect(saved.revision == 5 && !saved.writable)
        #expect((saved.value["unknown"] as? [String: Any])?["nested"] as? Int == 7)
    }
    @Test func filesAndCommandsParseAtBoundary() async throws {
        let fixture = APITransportFixture(responses: ["workspaceFiles/list": ["entries": [["name": "file", "type": "file", "size": 12]], "truncated": true],
            "workspaceFiles/read": ["text": "contents"], "fileReferences/list": [["path": "folder", "kind": "directory"]],
            "commands/list": [["name": "compact", "description": "Compact", "input": NSNull()]],
            "commands/execute": ["result": ["kind": "success", "text": "done"]]])
        let client = DSHClient(carrier: fixture); defer { client.close() }
        let files = FilesAPI(client: client), listing = try await files.list(workspaceFileScopeId: "s", path: ".")
        #expect(listing.truncated && listing.entries.first?.size == 12 && listing.entries.first?.name == "file")
        #expect(try await files.read(workspaceFileScopeId: "s", path: "file", offset: 1, limit: 50) == "contents")
        #expect(try await files.listReferences(agentId: "s", query: "f")?.first?.kind == "directory")
        let commands = CommandsAPI(client: client), command = try #require(try await commands.list(agentId: "s").first)
        #expect(command.name == "compact" && !command.acceptsInput)
        let response = try await commands.execute(agentId: "s", line: "/compact")
        #expect(response.kind == "success" && response.text == "done")
        #expect((fixture.calls.last?.args["submittedAttachments"] as? [Any])?.isEmpty == true)
    }
    @Test func typedStreamsRetainProjectionOrdering() async throws {
        let fixture = APITransportFixture(frames: ["session/control": [
            ["type": "baseline", "value": ["projections": ["s": ["asOfSeq": 10, "values": ["title": "first"]]]]],
            ["sessionId": "s", "key": "title", "value": "next", "seq": 11],
            ["sessionId": "s", "key": "title", "value": "stale", "seq": 9]],
            "workspace/follow": [["type": "baseline", "value": ["items": [["workspaceId": "w", "path": "/w"]]]]],
            "account/watch": [["status": "signed-out"]], "workspaceFiles/changes": [["kind": "change"]]])
        let client = DSHClient(carrier: fixture); defer { client.close() }
        var control = SessionControlState()
        for try await event in try await ControlAPI(client: client).follow() { control.apply(event) }
        #expect(control.values["s"]?.title == "next")
        var workspaces = WorkspaceState()
        for try await event in try await WorkspaceAPI(client: client).follow() { workspaces.apply(event) }
        #expect(workspaces.items.first?.id == "w")
        for try await state in try await AccountAPI(client: client, isLocal: true).watch() { #expect(state.status == "signed-out") }
        for try await change in try await FilesAPI(client: client).changes(workspaceFileScopeId: "s", path: ".") { #expect(change.kind == "change") }
    }
    @Test func malformedResponsesKeepStableErrors() async throws {
        let fixture = APITransportFixture(responses: ["workspace/create": [:], "schedule/delete": ["deleted": "unknown"], "session/attachment": ["data": "invalid base64"]])
        let client = DSHClient(carrier: fixture); defer { client.close() }
        do { _ = try await WorkspaceAPI(client: client).create(path: "/work"); Issue.record("Malformed workspace accepted") }
        catch let error as DSHError { #expect(error.code == "E_WORKSPACE_RESPONSE") }
        let task = try #require(ScheduleEntry(["id": "t", "sessionId": "s"]))
        do { _ = try await ScheduleAPI(client: client).delete(task); Issue.record("Unknown delete result accepted") }
        catch let error as DSHError { #expect(error.code == "E_SCHEDULE_RESPONSE") }
        do { _ = try await FilesAPI(client: client).attachment(sessionId: "s", attachmentId: "a"); Issue.record("Invalid attachment accepted") }
        catch let error as DSHError { #expect(error.code == "E_IMAGE_UNAVAILABLE") }
    }
    @Test func cancellingTypedStreamCancelsMuxSubscription() async throws {
        let fixture = APITransportFixture(finishStreams: false)
        let client = DSHClient(carrier: fixture); defer { client.close() }
        let stream = try await WorkspaceAPI(client: client).follow()
        let consumer = Task { for try await _ in stream {} }
        consumer.cancel()
        _ = try? await consumer.value
        for _ in 0..<1000 where fixture.cancelledStreams.isEmpty { await Task.yield() }
        #expect(fixture.cancelledStreams.count == 1)
    }
    @Test func jsonValueRoundTripAndFallbacks() throws {
        let value = try JSONValue(data: Data("{\"b\":true,\"i\":9007199254740991,\"n\":1.25,\"a\":[\"x\"],\"null\":null}".utf8))
        #expect(value["b"]?.bool == true && value["i"]?.int == 9007199254740991 && value["n"]?.double == 1.25)
        #expect(value["a"]?.strings == ["x"] && value["null"] == .null)
        #expect(try JSONValue(data: JSONEncoder().encode(value)) == value)
        #expect(JSONValue(["integer": 7, "boolean": false])["boolean"] == .bool(false))
        #expect(JSONValue(NSNumber(value: 60)).double == 60)
        #expect(JSONValue(NSNumber(value: 1.25)).double == 1.25)
        #expect(JSONValue([NSNumber(value: 1), NSNumber(value: 7)]).integers == [1, 7])
        #expect(DirectoryListing([:]).entries.isEmpty && WorkspaceFileListing([:]).entries.isEmpty)
    }
}
