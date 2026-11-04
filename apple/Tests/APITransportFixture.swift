// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
@testable import DSHClient

/// An in-memory carrier exercises the real client envelope/stream adapters without HTTP.
final class APITransportFixture: DSHCarrier, @unchecked Sendable {
    struct Call { let endpoint: String; let args: [String: Any] }
    private let lock = NSLock()
    private var recorded: [Call] = []
    private var cancelled: [String] = []
    private var eventSinks: [(String, @Sendable ([String: Any]) -> Void)] = []
    private var closes = 0
    let responses: [String: Any]
    let failures: [String: DSHError]
    let frames: [String: [[String: Any]]]
    let finishStreams: Bool
    let onCall: (@Sendable (String) async -> Void)?
    init(responses: [String: Any] = [:], failures: [String: DSHError] = [:], frames: [String: [[String: Any]]] = [:], finishStreams: Bool = true, onCall: (@Sendable (String) async -> Void)? = nil) {
        self.responses = responses; self.failures = failures; self.frames = frames; self.finishStreams = finishStreams; self.onCall = onCall
    }
    var calls: [Call] { lock.withLock { recorded } }
    var cancelledStreams: [String] { lock.withLock { cancelled } }
    func call(_ endpoint: String, args: [String: Any]) async throws -> Any? {
        lock.withLock { recorded.append(Call(endpoint: endpoint, args: args)) }
        await onCall?(endpoint)
        if let error = failures[endpoint] { throw error }
        guard let result = responses[endpoint] else { throw DSHError("E_TEST_UNEXPECTED_ENDPOINT") }; return result
    }
    func openLink(onFrame: @escaping @Sendable ([String: Any]) -> Void, onLost: @escaping @Sendable () -> Void) async throws -> DSHMuxLink {
        FixtureLink(owner: self, receive: onFrame)
    }
    var closeCount: Int { lock.withLock { closes } }
    func close() { lock.withLock { closes += 1 } }
    func emitEvent(_ value: [String: Any]) {
        let sinks = lock.withLock { eventSinks }
        for (id, receive) in sinks { receive(["type": "item", "streamId": id, "value": value]) }
    }
    private final class FixtureLink: DSHMuxLink, @unchecked Sendable {
        let owner: APITransportFixture
        let receive: @Sendable ([String: Any]) -> Void
        init(owner: APITransportFixture, receive: @escaping @Sendable ([String: Any]) -> Void) { self.owner = owner; self.receive = receive }
        func open(streamId: String, endpoint: String, args: [String: Any]) {
            owner.lock.withLock { owner.recorded.append(Call(endpoint: endpoint, args: args)) }
            if endpoint == "$events" {
                owner.lock.withLock { owner.eventSinks.append((streamId, receive)) }
                receive(["type": "item", "streamId": streamId, "value": ["type": "ready", "clientId": "test-client"]]); return
            }
            for value in owner.frames[endpoint] ?? [] { receive(["type": "item", "streamId": streamId, "value": value]) }
            if let error = owner.failures[endpoint] { receive(["type": "error", "streamId": streamId, "error": ["code": error.code]]) }
            else if owner.finishStreams { receive(["type": "end", "streamId": streamId]) }
        }
        func cancel(streamId: String) { owner.lock.withLock { owner.cancelled.append(streamId) } }
        func close() {}
    }
}
