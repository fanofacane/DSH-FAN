// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import DSHRuntime
import Foundation

/// The runtime boundary used by UI state; tests never need to boot an iSH kernel.
@MainActor protocol EngineControlling: AnyObject {
    var onEvent: (@MainActor (RuntimeEvent) -> Void)? { get set }
    func status() async -> RuntimeStatus
    func connection() async -> RuntimeConnection?
    func install(force: Bool, dropKept: Bool) async throws
    func start(mode: RuntimeMode?, environment: [String: String]) async throws
    func stop() async throws
    func reset(keep: [String]) async throws
    func setAutoSafe(_ enabled: Bool) async
    func logTail(lines: Int) async -> [String]
    func replyPreferences() async throws -> String
    func saveReplyPreferences(_ text: String, expected: String) async throws
    #if DEBUG
    // Smoke-test hook; RuntimeEngine only has it in Debug builds.
    func testProcessSnapshot() async -> (processes: [[String: NSNumber]], booted: Bool, pending: Bool)
    #endif
}

extension EngineControlling {
    func install() async throws { try await install(force: false, dropKept: false) }
    func start(mode: RuntimeMode? = nil) async throws { try await start(mode: mode, environment: [:]) }
    func reset() async throws { try await reset(keep: []) }
}
extension RuntimeEngine: EngineControlling {}

/// Host selection and authenticated client creation can be replaced together.
@MainActor protocol HostProviding: AnyObject {
    var activeHost: ActiveHost? { get }
    var isRemote: Bool { get }
    var sessionDirectory: String? { get }
    func select(_ id: String?)
    func makeClient(forceRestart: Bool) async throws -> DSHClient
}
extension HostStore: HostProviding {}

@MainActor protocol TaskNotifying: AnyObject {
    @discardableResult
    func notify(_ kind: TaskNotifications.Kind, eventId: String, sessionId: String, hostId: String?) async -> Bool
    func finishGrace()
}
extension TaskNotifications: TaskNotifying {}

/// Chat and engine coordination use lifecycle events, without owning phone UI state.
@MainActor protocol PhoneControlling: AnyObject {
    func beforeEngineStart() async
    func engineStopped() async
    func hostConnectionChanged()
    func sessionStatus(_ sessionId: String, running: Bool)
}
extension PhoneController: PhoneControlling {}

func appErrorCode(_ error: Error) -> String { (error as? DSHError)?.code ?? "E_TRANSPORT" }
