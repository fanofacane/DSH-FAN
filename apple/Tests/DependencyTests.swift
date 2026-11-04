// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHRuntime
import Foundation
import Testing
@testable import DSH

@MainActor struct DependencyTests {
    @Test func engineStoreUsesInjectedLifecycle() async throws {
        let runtime = FakeEngine()
        let phone = FakePhone()
        let store = EngineModel(runtime: runtime, phone: phone)
        store.startSafe()
        // The busy guard must also work when a fake runtime is used.
        store.start()
        for _ in 0..<100 where store.busy { await Task.yield() }
        #expect(!store.busy)
        #expect(runtime.starts == [.safe])
        #expect(phone.preparations == 1)
        #expect(store.status.phase == .running)
        runtime.failure = RuntimeError("E_INJECTED_START")
        store.start()
        for _ in 0..<100 where store.busy { await Task.yield() }
        #expect(store.actionError == "E_INJECTED_START")
        #expect(phone.preparations == 2)
    }

    @Test func unitTestHostSkipsAutomaticEnginePreparation() async {
        #expect(AppLaunchPolicy.isUnitTestHost(environment: ["XCTestConfigurationFilePath": ""], arguments: []))
        #expect(AppLaunchPolicy.isUnitTestHost(environment: [:], arguments: ["-dsh-unit-tests"]))
        #expect(!AppLaunchPolicy.isUnitTestHost(environment: [:], arguments: ["-dsh-chat-smoke", "-dsh-dump-log"]))
        #expect(!AppLaunchPolicy.isUnitTestHost(environment: ["OTHER_TEST_SETTING": "1"], arguments: []))
        #expect(AppLaunchPolicy.isUnitTestHost)
        let runtime = FakeEngine(), phone = FakePhone()
        let store = EngineModel(runtime: runtime, phone: phone)
        store.prepareOnLaunch(force: true)
        for _ in 0..<20 { await Task.yield() }
        #expect(runtime.starts.isEmpty && phone.preparations == 0 && !store.busy)
    }

    @Test func petManifestKeepsFoundationNumericValues() throws {
        let directory = try #require(Bundle.main.url(forResource: "deepy-whale", withExtension: nil))
        let raw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("pack.json"))) as? [String: Any])
        let pack = try PetPack(directory: directory)
        let canvas = raw["canvas"] as? [String: Any]
        #expect(Double(pack.canvas.width) == (canvas?["w"] as? Double ?? 52))
        #expect(Double(pack.canvas.height) == (canvas?["h"] as? Double ?? 52))
        let animations = try #require(raw["animations"] as? [String: [String: Any]])
        let name = try #require(animations.keys.sorted().first)
        let animation = try #require(pack.animation(name))
        let frames = animations[name]?["frames"] as? [[String: Any]] ?? []
        #expect(animation.durations == frames.map { ($0["ms"] as? Double ?? 50) / 1000 })
    }

}

@MainActor final class FakePhone: PhoneControlling {
    var preparations = 0
    var connectionChanges = 0
    var sessionStates: [String: Bool] = [:]
    func beforeEngineStart() async { preparations += 1 }
    func engineStopped() async {}
    func hostConnectionChanged() { connectionChanges += 1 }
    func sessionStatus(_ sessionId: String, running: Bool) { sessionStates[sessionId] = running }
}

@MainActor private final class FakeEngine: EngineControlling {
    var onEvent: (@MainActor (RuntimeEvent) -> Void)?
    var starts: [RuntimeMode?] = []
    var failure: RuntimeError?
    func status() async -> RuntimeStatus { RuntimeStatus() }
    func connection() async -> RuntimeConnection? { nil }
    func install(force: Bool, dropKept: Bool) async throws {}
    func start(mode: RuntimeMode?, environment: [String: String]) async throws {
        if let failure { throw failure }
        starts.append(mode)
        var status = RuntimeStatus(); status.phase = .running
        onEvent?(.status(status))
    }
    func stop() async throws {}
    func reset(keep: [String]) async throws {}
    func setAutoSafe(_ enabled: Bool) async {}
    func logTail(lines: Int) async -> [String] { [] }
    func replyPreferences() async throws -> String { "" }
    func saveReplyPreferences(_ text: String, expected: String) async throws {}
    func testProcessSnapshot() async -> (processes: [[String: NSNumber]], booted: Bool, pending: Bool) { ([], false, false) }
}
