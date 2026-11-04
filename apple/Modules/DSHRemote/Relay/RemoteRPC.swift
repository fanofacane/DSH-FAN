// SPDX-License-Identifier: AGPL-3.0-or-later
// Noise IK secure channel over the relay transport, and the RPC client inside
// it (port of 原 Flutter 版 dsh_remote/lib/src/channel/{secure_channel,rpc_client}.dart;
// upstream ds-harness-remote, MIT). Fails closed on any bad input.
import Foundation

final class SecureChannel: @unchecked Sendable {
    private let transport: RelayTransport
    private let noise: NoiseIKSession
    private let incoming = SecureMessageCodec()
    private let outgoing = SecureMessageCodec()
    private let lock = NSLock()
    private var handshake: CheckedContinuation<Void, Error>?
    private var onMessage: ((Data) -> Void)?
    private var onClosed: ((RemoteFailure) -> Void)?
    private var backlog: [Data] = []
    private(set) var closedReason: RemoteFailure?
    private var closed = false

    var connectionId: String { transport.connectionId ?? "" }

    private init(transport: RelayTransport, noise: NoiseIKSession) { self.transport = transport; self.noise = noise }

    static func establish(transport: RelayTransport, clientPrivateKey: Data, clientDeviceId: String,
                          hostDeviceId: String, hostIdentityKey: Data, timeout: TimeInterval = 10) async throws -> SecureChannel {
        guard let connectionId = transport.connectionId, transport.deviceId == clientDeviceId, transport.hostDeviceId == hostDeviceId else {
            transport.close()
            throw RemoteFailure("SECURE_CHANNEL_FAILED", "The relay connection is bound to an unexpected device.", retryable: false)
        }
        let noise: NoiseIKSession
        do {
            noise = try NoiseIKSession(role: .initiator, localPrivateKey: clientPrivateKey, remotePublicKey: hostIdentityKey,
                                       prologue: NoiseIKSession.prologue(connectionId: connectionId, hostDeviceId: hostDeviceId,
                                                                         clientDeviceId: clientDeviceId))
        } catch let error as NoiseError {
            transport.close()
            throw RemoteFailure(error.code, error.message, retryable: false)
        }
        let channel = SecureChannel(transport: transport, noise: noise)
        try await channel.runHandshake(timeout: timeout)
        return channel
    }

    private func runHandshake(timeout: TimeInterval) async throws {
        let timer = DispatchWorkItem { [weak self] in
            self?.finishHandshake(RemoteFailure("SECURE_CHANNEL_FAILED", "Noise IK handshake timed out.", retryable: true))
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        defer { timer.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.withLock { handshake = continuation }
            transport.listen(
                onData: { [weak self] data, counter in self?.receive(data, counter: counter) },
                onHandshake: { [weak self] step, data in self?.receiveHandshake(step, data) },
                onClosed: { [weak self] reason in
                    self?.finishHandshake(reason)
                    self?.fail(reason)
                })
            do {
                let first = try lock.withLock { try noise.writeHandshake() }
                try transport.sendHandshake(step: 1, data: first)
            } catch {
                let failure = (error as? RemoteFailure)
                    ?? (error as? NoiseError).map { RemoteFailure($0.code, $0.message, retryable: false) }
                    ?? RemoteFailure("SECURE_CHANNEL_FAILED", "\(error)", retryable: true)
                finishHandshake(failure)
            }
        }
    }

    private func finishHandshake(_ error: RemoteFailure?) {
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Error>? in defer { handshake = nil }; return handshake }
        guard let waiter else { return }
        if let error { waiter.resume(throwing: error); fail(error) } else { waiter.resume() }
    }

    private func receiveHandshake(_ step: Int, _ data: Data) {
        do {
            guard step == 2 else { throw NoiseError("NOISE_HANDSHAKE_ORDER", "Out-of-order handshake message.") }
            try lock.withLock {
                _ = try noise.readHandshake(data)
                guard noise.complete else { throw NoiseError("SECURE_CHANNEL_FAILED", "Handshake did not complete.") }
            }
            finishHandshake(nil)
        } catch let error as NoiseError {
            let code = error.code == "PEER_IDENTITY_MISMATCH" ? error.code : "SECURE_CHANNEL_FAILED"
            finishHandshake(RemoteFailure(code, error.message, retryable: code != "PEER_IDENTITY_MISMATCH"))
        } catch {
            finishHandshake(RemoteFailure("SECURE_CHANNEL_FAILED", "\(error)", retryable: true))
        }
    }

    private func receive(_ ciphertext: Data, counter: Int?) {
        do {
            let message: Data? = try lock.withLock {
                guard !closed else { return nil }
                guard noise.complete else { throw RemoteProtocolError("Ciphertext before the handshake completed.") }
                if let counter, UInt64(counter) != noise.receivingCounter { throw RemoteProtocolError("Relay counter is duplicated or out of order.") }
                return try incoming.decode(try noise.decrypt(ciphertext))
            }
            guard let message else { return }
            let handler = lock.withLock { () -> ((Data) -> Void)? in
                if onMessage == nil { backlog.append(message) }
                return onMessage
            }
            handler?(message)
        } catch {
            fail(RemoteFailure("SECURE_CHANNEL_FAILED", "Secure channel input rejected: \(error)", retryable: true))
        }
    }

    func listen(onMessage: @escaping (Data) -> Void, onClosed: @escaping (RemoteFailure) -> Void) {
        let (pending, reason) = lock.withLock { () -> ([Data], RemoteFailure?) in
            self.onMessage = onMessage; self.onClosed = onClosed
            defer { backlog = [] }
            return (backlog, closedReason)
        }
        pending.forEach(onMessage)
        if let reason { onClosed(reason) }
    }

    func send(_ message: Data) throws {
        try lock.withLock {
            guard !closed else { throw RemoteFailure(closedReason?.code ?? "SECURE_CHANNEL_FAILED", "The secure channel is closed.", retryable: true) }
            do {
                for fragment in try outgoing.encode(message) {
                    let counter = noise.sendingCounter
                    try transport.send(ciphertext: try noise.encrypt(fragment), counter: counter)
                }
            } catch let error as RemoteProtocolError where error.code == "FRAME_TOO_LARGE" {
                throw RemoteFailure("FRAME_TOO_LARGE", error.message, retryable: false)
            }
        }
    }

    func fail(_ reason: RemoteFailure) {
        let handler = lock.withLock { () -> ((RemoteFailure) -> Void)? in
            guard !closed else { return nil }
            closed = true
            closedReason = reason
            noise.destroy(); incoming.reset(); outgoing.reset()
            defer { onClosed = nil }
            return onClosed
        }
        transport.close()
        handler?(reason)
    }

    func close() { fail(RemoteFailure("CLIENT_CLOSED", "The client closed the secure channel.", retryable: false)) }
}

/// An RPC failure. `isLocal`: raised on this side (timeout, closed channel), so the outcome is unknown.
struct RemoteRPCError: Error, CustomStringConvertible {
    let code: String
    let message: String
    var details: Any?
    var retryable = false
    var isLocal = false
    var description: String { "\(code): \(message)" }
    var isTransportClosed: Bool { code == "TRANSPORT_CLOSED" || code == "CLIENT_CLOSED" }
}

final class RemoteRPCClient: @unchecked Sendable {
    struct Event { let name: String; let data: Any? }
    private let channel: SecureChannel
    private let lock = NSLock()
    private var pending: [String: (method: String, continuation: CheckedContinuation<Any?, Error>, timer: DispatchWorkItem)] = [:]
    private var eventHandlers: [UUID: (Event) -> Void] = [:]
    private var doneHandlers: [(RemoteFailure) -> Void] = []
    private(set) var doneReason: RemoteFailure?
    private var lastInbound = Date()

    init(channel: SecureChannel) {
        self.channel = channel
        channel.listen(onMessage: { [weak self] in self?.receive($0) }, onClosed: { [weak self] in self?.closed($0) })
    }

    var isClosed: Bool { lock.withLock { doneReason != nil } }
    var sinceInbound: TimeInterval { lock.withLock { Date().timeIntervalSince(lastInbound) } }

    @discardableResult
    func onEvent(_ handler: @escaping (Event) -> Void) -> UUID {
        let id = UUID()
        lock.withLock { eventHandlers[id] = handler }
        return id
    }
    func removeEventHandler(_ id: UUID) { _ = lock.withLock { eventHandlers.removeValue(forKey: id) } }

    /// Called once with the reason the channel ended (immediately if it already has).
    func onDone(_ handler: @escaping (RemoteFailure) -> Void) {
        let reason = lock.withLock { () -> RemoteFailure? in
            if doneReason == nil { doneHandlers.append(handler) }
            return doneReason
        }
        if let reason { handler(reason) }
    }

    func call(_ method: String, _ params: Any = [String: Any](), timeout: TimeInterval = 35) async throws -> Any? {
        let (id, data) = RemoteMessage.request(method, params)
        return try await withCheckedThrowingContinuation { continuation in
            let timer = DispatchWorkItem { [weak self] in
                self?.reject(id, RemoteRPCError(code: "RPC_TIMEOUT", message: "RPC \(method) timed out.", retryable: true, isLocal: true))
            }
            let refused: RemoteRPCError? = lock.withLock {
                if doneReason != nil { return RemoteRPCError(code: "TRANSPORT_CLOSED", message: "RPC \(method): the remote channel is closed.", isLocal: true) }
                if pending.count >= 128 { return RemoteRPCError(code: "RATE_LIMITED", message: "Too many pending remote RPCs.", retryable: true, isLocal: true) }
                pending[id] = (method, continuation, timer)
                return nil
            }
            if let refused { continuation.resume(throwing: refused); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
            do {
                try channel.send(data)
            } catch let failure as RemoteFailure where failure.code == "FRAME_TOO_LARGE" {
                reject(id, RemoteRPCError(code: "FRAME_TOO_LARGE", message: failure.message, isLocal: true))
            } catch {
                reject(id, RemoteRPCError(code: "TRANSPORT_CLOSED", message: "RPC \(method) send failed: \(error)", retryable: true, isLocal: true))
            }
        }
    }

    private func take(_ id: String) -> CheckedContinuation<Any?, Error>? {
        lock.withLock {
            guard let entry = pending.removeValue(forKey: id) else { return nil }
            entry.timer.cancel()
            return entry.continuation
        }
    }

    private func reject(_ id: String, _ error: RemoteRPCError) { take(id)?.resume(throwing: error) }

    private func receive(_ bytes: Data) {
        lock.withLock { lastInbound = Date() }
        let message: RemoteMessage
        do { message = try RemoteMessage.decode(bytes) } catch {
            channel.fail(RemoteFailure("SECURE_CHANNEL_FAILED", "Invalid Remote message: \(error)", retryable: true))
            return
        }
        let payload = message.payload as? [String: Any]
        switch message.type {
        case "rpc.response":
            guard let id = payload?["requestId"] as? String else { return }
            take(id)?.resume(returning: payload?["result"])
        case "rpc.error":
            guard let id = payload?["requestId"] as? String, let code = payload?["code"] as? String, !code.isEmpty,
                  let text = payload?["message"] as? String else { return }
            take(id)?.resume(throwing: RemoteRPCError(code: code, message: text, details: payload?["details"],
                                                      retryable: payload?["retryable"] as? Bool ?? false))
        case "event":
            guard let name = payload?["event"] as? String else { return }
            let handlers = lock.withLock { Array(eventHandlers.values) }
            let event = Event(name: name, data: payload?["data"])
            handlers.forEach { $0(event) }
        default:
            break
        }
    }

    private func closed(_ reason: RemoteFailure) {
        let (entries, handlers) = lock.withLock { () -> ([(String, CheckedContinuation<Any?, Error>, DispatchWorkItem)], [(RemoteFailure) -> Void]) in
            guard doneReason == nil else { return ([], []) }
            doneReason = reason
            defer { pending = [:]; doneHandlers = []; eventHandlers = [:] }
            return (pending.map { ($0.value.method, $0.value.continuation, $0.value.timer) }, doneHandlers)
        }
        let code = reason.code == "CLIENT_CLOSED" ? "CLIENT_CLOSED" : "TRANSPORT_CLOSED"
        for (method, continuation, timer) in entries {
            timer.cancel()
            continuation.resume(throwing: RemoteRPCError(code: code, message: "RPC \(method) ended: \(reason.message)",
                                                          retryable: reason.retryable, isLocal: true))
        }
        handlers.forEach { $0(reason) }
    }

    func close() { channel.close() }
}
