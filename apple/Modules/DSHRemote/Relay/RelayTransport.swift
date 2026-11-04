// SPDX-License-Identifier: AGPL-3.0-or-later
// Control WebSocket to the ds-harness-remote Server (port of
// 原 Flutter 版 dsh_remote/lib/src/transport/relay_transport.dart; upstream MIT):
// hello → connect.request → connect.accepted, the Noise handshake frames, and
// ciphertext on the Control socket or on an assigned Relay node data socket.
// Relay only: the WebRTC direct path is not offered.
import Foundation

/// A remote failure with a stable code (README "failure.code" table).
public struct RemoteFailure: Error, Sendable, Equatable, CustomStringConvertible {
    public let code: String
    public let message: String
    public let retryable: Bool
    public init(_ code: String, _ message: String, retryable: Bool) { self.code = code; self.message = message; self.retryable = retryable }
    public var description: String { "\(code): \(message)" }

    static let terminalCodes: Set<String> = [
        "CONNECTION_REPLACED", "CONNECTION_REJECTED", "PEER_IDENTITY_MISMATCH", "MEMBERSHIP_REQUIRED", "DEVICE_REVOKED",
        "DEVICE_NOT_FOUND", "CAPABILITY_NOT_SUPPORTED", "UNSUPPORTED_VERSION", "ACCOUNT_AUTH_REQUIRED",
        "HOST_NOT_TRUSTED", "HARNESS_VERSION_INCOMPATIBLE",
    ]
}

final class RelayTransport: @unchecked Sendable {
    private static let retryableCodes: Set<String> = [
        "CONNECTION_FAILED", "HOST_OFFLINE", "RATE_LIMITED", "SLOW_CONSUMER", "RELAY_UNAVAILABLE", "TOKEN_EXPIRED", "AUTH_INVALID",
    ]
    private static let offered = ["transport.relay", "transport.relay.attach"]

    let deviceId: String
    let hostDeviceId: String
    private let session: URLSession
    private let control: URLSessionWebSocketTask
    private var data: URLSessionWebSocketTask?
    private let queue = DispatchQueue(label: "dsh.remote.relay")
    /// Handlers run here, in arrival order, never on `queue` (they may send).
    private let delivery = DispatchQueue(label: "dsh.remote.relay.delivery")
    private var limits = RemoteWire.Limits()
    private(set) var connectionId: String?
    private var relayEpoch: Int?
    private var heartbeatMs = 25_000
    private var lastReceived = Date()
    private var watchdog: DispatchSourceTimer?
    private var closed = false
    private var ready: CheckedContinuation<Void, Error>?
    private var onData: ((Data, Int?) -> Void)?
    private var onHandshake: ((Int, Data) -> Void)?
    private var onClosed: ((RemoteFailure) -> Void)?
    private var backlog: [() -> Void] = []
    private var pendingClose: RemoteFailure?

    private init(session: URLSession, control: URLSessionWebSocketTask, deviceId: String, hostDeviceId: String) {
        self.session = session; self.control = control; self.deviceId = deviceId; self.hostDeviceId = hostDeviceId
    }

    static func connect(url: URL, deviceId: String, accessToken: String, hostDeviceId: String, clientVersion: String,
                        timeout: TimeInterval = 10) async throws -> RelayTransport {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        let session = URLSession(configuration: config)
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = RemoteWire.maxRelayFrameBytes + 1024
        let transport = RelayTransport(session: session, control: task, deviceId: deviceId, hostDeviceId: hostDeviceId)
        task.resume()
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await transport.open(accessToken: accessToken, clientVersion: clientVersion) }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw RemoteFailure("CONNECTION_FAILED", "Relay control handshake timed out.", retryable: true)
                }
                try await group.next()
                group.cancelAll()
            }
            return transport
        } catch {
            transport.abort()
            if let failure = error as? RemoteFailure { throw failure }
            throw RemoteFailure("CONNECTION_FAILED", "Control WebSocket failed: \(error.localizedDescription)", retryable: true)
        }
    }

    private func open(accessToken: String, clientVersion: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                ready = continuation
                receive(control, data: false)
                sendControl("hello", ["role": "client", "deviceId": deviceId, "accessToken": accessToken,
                                      "protocols": [RemoteWire.protocolVersion], "capabilities": Self.offered,
                                      "clientVersion": clientVersion])
            }
        }
    }

    // MARK: Receive

    private func receive(_ task: URLSessionWebSocketTask, data isData: Bool) {
        task.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                switch result {
                case .failure(let error):
                    if isData {
                        self.fail(RemoteFailure("CONNECTION_FAILED", "Relay data socket closed: \(error.localizedDescription)", retryable: true))
                    } else {
                        self.fail(self.closeReason(error))
                    }
                case .success(let message):
                    guard !self.closed else { return }
                    self.lastReceived = Date()
                    guard case .string(let text) = message else {
                        self.fail(RemoteFailure("PROTOCOL_MISMATCH", "Relay frames must be text JSON.", retryable: false))
                        return
                    }
                    do {
                        if isData { try self.handleData(try RemoteWire.decodeData(text, limits: self.limits)) }
                        else { try self.handle(try RemoteWire.decodeControl(text, limits: self.limits)) }
                    } catch let error as RemoteProtocolError {
                        let code = error.code == "INVALID_MESSAGE" ? "PROTOCOL_MISMATCH" : error.code
                        self.fail(RemoteFailure(code, error.message, retryable: false))
                        return
                    } catch {
                        self.fail(RemoteFailure("PROTOCOL_MISMATCH", "\(error)", retryable: false))
                        return
                    }
                    if !self.closed { self.receive(task, data: isData) }
                }
            }
        }
    }

    private func closeReason(_ error: Error) -> RemoteFailure {
        let code = control.closeCode.rawValue
        let reason = control.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if let http = control.response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
            return RemoteFailure("AUTH_INVALID", "Control WebSocket refused (HTTP \(http.statusCode)).", retryable: true)
        }
        if code == 4003 {
            return RemoteFailure("CONNECTION_REPLACED", "Another connection of this device replaced the Control channel.", retryable: false)
        }
        let known = reason.range(of: #"^[A-Z][A-Z0-9_]+$"#, options: .regularExpression) != nil ? reason : nil
        return RemoteFailure(known ?? "CONNECTION_FAILED",
                             "Control channel closed (\(code) \(reason.isEmpty ? error.localizedDescription : reason))",
                             retryable: known == nil || Self.retryableCodes.contains(known!))
    }

    private func handle(_ frame: RemoteWire.Frame) throws {
        let p = frame.payload
        switch frame.type {
        case "hello.ack":
            guard ready != nil, connectionId == nil else { throw RemoteProtocolError("Unexpected hello.ack.") }
            let negotiated = p["capabilities"] as? [String] ?? ["transport.relay"]
            guard Set(negotiated).isSubset(of: Set(Self.offered)), negotiated.contains("transport.relay") else {
                throw RemoteProtocolError("Server did not negotiate the Relay capability.", "CAPABILITY_NOT_SUPPORTED")
            }
            limits = RemoteWire.Limits(control: p["maxControlFrameBytes"] as? Int ?? RemoteWire.maxControlFrameBytes,
                                       relay: p["maxRelayFrameBytes"] as? Int ?? RemoteWire.maxRelayFrameBytes)
            heartbeatMs = p["heartbeatIntervalMs"] as? Int ?? heartbeatMs
            sendControl("connect.request", ["hostDeviceId": hostDeviceId, "preferredTransports": ["relay"]])
        case "connect.accepted":
            guard ready != nil, connectionId == nil else { throw RemoteProtocolError("Unexpected connect.accepted.") }
            connectionId = p["connectionId"] as? String
            startWatchdog()
            if let endpoint = (p["relayEndpoint"] as? String).flatMap(URL.init(string:)), let ticket = p["relayTicket"] as? String {
                relayEpoch = p["relayEpoch"] as? Int
                attach(endpoint, ticket: ticket)
            } else {
                resolveReady(nil)
            }
        case "connect.rejected":
            if let id = connectionId, p["connectionId"] as? String != id { return }
            let code = p["code"] as? String ?? "CONNECTION_REJECTED"
            fail(RemoteFailure(code, p["message"] as? String ?? "The Host rejected the connection.",
                               retryable: Self.retryableCodes.contains(code)))
        case "error":
            if let id = p["connectionId"] as? String, let mine = connectionId, id != mine { return }
            let code = p["code"] as? String ?? "CONNECTION_FAILED"
            fail(RemoteFailure(code, p["message"] as? String ?? "", retryable: p["retryable"] as? Bool == true || Self.retryableCodes.contains(code)))
        case "relay":
            if data == nil { try receiveRelay(p) }
        case "secure.handshake":
            try receiveHandshake(p)
        case "ping":
            sendControl("pong", ["nonce": p["nonce"] ?? ""])
        default:
            break
        }
    }

    private func handleData(_ frame: RemoteWire.Frame) throws {
        let p = frame.payload
        switch frame.type {
        case "relay.ready":
            guard ready != nil else { return }
            guard p["connectionId"] as? String == connectionId, relayEpoch == nil || p["epoch"] as? Int == relayEpoch else {
                throw RemoteProtocolError("Relay data attach does not match the assigned connection.")
            }
            sendControl("transport.selected", ["connectionId": connectionId!, "targetDeviceId": hostDeviceId, "transport": "relay"])
            resolveReady(nil)
        case "relay.detach":
            fail(RemoteFailure("CONNECTION_FAILED", "The Host detached from the Relay node.", retryable: true))
        case "ping":
            sendData("pong", p)
        case "relay":
            try RemoteWire.validate("relay", p); try receiveRelay(p)
        case "secure.handshake":
            try RemoteWire.validate("secure.handshake", p); try receiveHandshake(p)
        default:
            break
        }
    }

    private func receiveRelay(_ p: [String: Any]) throws {
        guard p["connectionId"] as? String == connectionId, p["targetDeviceId"] as? String == deviceId,
              let bytes = (p["ciphertext"] as? String).flatMap(RemoteBytes.fromBase64URL), let counter = p["counter"] as? Int else {
            throw RemoteProtocolError("Received a relay frame for an unknown connection.")
        }
        deliver { [weak self] in self?.onData?(bytes, counter) }
    }

    private func receiveHandshake(_ p: [String: Any]) throws {
        guard p["connectionId"] as? String == connectionId, p["targetDeviceId"] as? String == deviceId,
              let bytes = (p["data"] as? String).flatMap(RemoteBytes.fromBase64URL), let step = p["step"] as? Int else {
            throw RemoteProtocolError("Received a handshake frame for an unknown connection.")
        }
        deliver { [weak self] in self?.onHandshake?(step, bytes) }
    }

    private func attach(_ endpoint: URL, ticket: String) {
        let task = session.webSocketTask(with: endpoint)
        task.maximumMessageSize = RemoteWire.maxRelayFrameBytes + 1024
        data = task
        task.resume()
        receive(task, data: true)
        sendData("relay.attach", ["connectionId": connectionId!, "deviceId": deviceId, "peerDeviceId": hostDeviceId, "ticket": ticket])
    }

    private func deliver(_ action: @escaping () -> Void) {
        if onData == nil { backlog.append(action) } else { delivery.async(execute: action) }
    }

    private func startWatchdog() {
        watchdog?.cancel()
        let period = Double(heartbeatMs) / 1000
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + period, repeating: period)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if Date().timeIntervalSince(self.lastReceived) > period * 3 {
                self.fail(RemoteFailure("CONNECTION_FAILED", "The Server Control channel went silent.", retryable: true))
            }
        }
        timer.resume()
        watchdog = timer
    }

    private func resolveReady(_ error: RemoteFailure?) {
        guard let waiter = ready else { return }
        ready = nil
        if let error { waiter.resume(throwing: error) } else { waiter.resume() }
    }

    // MARK: Send

    private func sendControl(_ type: String, _ payload: [String: Any]) {
        guard !closed else { return }
        do {
            let text = try RemoteWire.encode(RemoteWire.Frame(type, payload), limits: limits)
            control.send(.string(text)) { [weak self] error in
                if let error { self?.queue.async { self?.fail(RemoteFailure("CONNECTION_FAILED", "Control send failed: \(error.localizedDescription)", retryable: true)) } }
            }
        } catch {
            fail(RemoteFailure("FRAME_TOO_LARGE", "\(error)", retryable: false))
        }
    }

    private func sendData(_ type: String, _ payload: [String: Any]) {
        guard !closed, let data else { return }
        let text = RemoteBytes.encodeJSON(RemoteWire.Frame(type, payload).json)
        data.send(.string(text)) { [weak self] error in
            if let error { self?.queue.async { self?.fail(RemoteFailure("CONNECTION_FAILED", "Relay data send failed: \(error.localizedDescription)", retryable: true)) } }
        }
    }

    func listen(onData: @escaping (Data, Int?) -> Void, onHandshake: @escaping (Int, Data) -> Void,
                onClosed: @escaping (RemoteFailure) -> Void) {
        queue.sync {
            self.onData = onData; self.onHandshake = onHandshake; self.onClosed = onClosed
            let pending = backlog; backlog = []
            pending.forEach { delivery.async(execute: $0) }
            if let reason = pendingClose { pendingClose = nil; delivery.async { onClosed(reason) } }
        }
    }

    func sendHandshake(step: Int, data bytes: Data) throws {
        try queue.sync {
            guard !closed, let id = connectionId else { throw RemoteFailure("CONNECTION_FAILED", "The relay connection is not open.", retryable: true) }
            sendControl("secure.handshake", ["connectionId": id, "targetDeviceId": hostDeviceId, "step": step,
                                             "data": RemoteBytes.base64URL(bytes)])
        }
    }

    func send(ciphertext: Data, counter: UInt64) throws {
        try queue.sync {
            guard !closed, let id = connectionId else { throw RemoteFailure("CONNECTION_FAILED", "The relay connection is not open.", retryable: true) }
            let payload: [String: Any] = ["connectionId": id, "targetDeviceId": hostDeviceId, "counter": Int(counter),
                                          "ciphertext": RemoteBytes.base64URL(ciphertext)]
            if data != nil { sendData("relay", payload) } else { sendControl("relay", payload) }
        }
    }

    /// Runs on `queue`.
    private func fail(_ reason: RemoteFailure) {
        guard !closed else { return }
        closed = true
        watchdog?.cancel()
        if ready != nil {
            resolveReady(reason)
        } else if let onClosed {
            self.onClosed = nil
            delivery.async { onClosed(reason) }
        } else {
            pendingClose = reason
        }
        data?.cancel(with: .normalClosure, reason: nil)
        control.cancel(with: .normalClosure, reason: nil)
        session.finishTasksAndInvalidate()
    }

    private func abort() {
        queue.async { [self] in
            closed = true
            watchdog?.cancel()
            resolveReady(RemoteFailure("CONNECTION_FAILED", "aborted", retryable: true))
            data?.cancel(with: .normalClosure, reason: nil)
            control.cancel(with: .normalClosure, reason: nil)
            session.finishTasksAndInvalidate()
        }
    }

    func close() {
        queue.async { [self] in
            guard !closed else { return }
            closed = true
            onClosed = nil
            watchdog?.cancel()
            data?.cancel(with: .normalClosure, reason: Data("client closed".utf8))
            control.cancel(with: .normalClosure, reason: Data("client closed".utf8))
            session.finishTasksAndInvalidate()
        }
    }
}
