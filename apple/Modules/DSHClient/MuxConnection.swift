// SPDX-License-Identifier: AGPL-3.0-or-later
// `/api/remote.mux`: many logical streams over one WebSocket.
// Uplink:   {type: open|cancel, streamId, endpoint?, payload?}
// Downlink: {type: item|end|error, streamId, value?|error?}
import Foundation

/// A JSON object from the mux. Values come from JSONSerialization and are not mutated.
public struct MuxItem: @unchecked Sendable {
    public let value: [String: Any]
}

public final class MuxConnection: @unchecked Sendable {
    private weak var client: DSHClient?
    private var socket: URLSessionWebSocketTask?
    /// Remote tunnel link (instead of `socket`).
    private var link: DSHMuxLink?
    private let lock = NSLock()
    private var streams: [String: AsyncThrowingStream<MuxItem, Error>.Continuation] = [:]
    private var open = false
    private var eventsStreamId = ""
    private var readyWaiter: CheckedContinuation<Bool, Never>?
    private var readyClientId: String?

    init(client: DSHClient) { self.client = client }

    public var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return open }
    /// The `$events` client id from `ready`; required to answer host requests.
    public var clientId: String? { lock.lock(); defer { lock.unlock() }; return readyClientId }

    func connect() async throws {
        guard let client else { throw DSHError("E_CLIENT_GONE") }
        if let carrier = client.carrier { return try await connect(carrier) }
        var components = URLComponents(url: client.baseURL.appendingPathComponent("api/remote.mux"), resolvingAgainstBaseURL: false)!
        components.scheme = client.baseURL.scheme == "https" ? "wss" : "ws"
        var request = URLRequest(url: components.url!)
        // Same as DshConnection.connectWebSocket: cookie, no browser Origin.
        request.setValue(client.authCookie, forHTTPHeaderField: "Cookie")
        let task = client.session.webSocketTask(with: request)
        task.maximumMessageSize = 64 * 1024 * 1024
        lock.withLock { socket = task; open = true }
        task.resume()
        receiveLoop(task)
        // `$events` must answer `ready` before any other stream is trusted.
        // It is handled in `dispatch`, not as a consumer stream.
        let id = UUID().uuidString
        let ready: Bool = await withCheckedContinuation { continuation in
            lock.withLock { eventsStreamId = id; readyWaiter = continuation }
            do { try sendFrame(task, ["type": "open", "streamId": id, "endpoint": "$events", "payload": ["args": [String: Any]()]]) }
            catch { resolveReady(false) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 20) { [weak self] in self?.resolveReady(false) }
        }
        guard ready else { close(); throw DSHError("E_MUX_NOT_READY") }
    }

    private func connect(_ carrier: DSHCarrier) async throws {
        let opened = try await carrier.openLink(
            onFrame: { [weak self] frame in self?.dispatch(frame) },
            onLost: { [weak self] in self?.lost() })
        lock.withLock { link = opened; open = true }
        let id = UUID().uuidString
        let ready: Bool = await withCheckedContinuation { continuation in
            lock.withLock { eventsStreamId = id; readyWaiter = continuation }
            opened.open(streamId: id, endpoint: "$events", args: [:])
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) { [weak self] in self?.resolveReady(false) }
        }
        guard ready else { close(); throw DSHError("E_MUX_NOT_READY") }
    }

    private func resolveReady(_ value: Bool) {
        lock.lock(); let waiter = readyWaiter; readyWaiter = nil; lock.unlock()
        waiter?.resume(returning: value)
    }

    /// Opens a logical stream. Iterate the returned sequence; cancelling the
    /// consuming task sends `cancel` upstream.
    public func open(endpoint: String, args: [String: Any] = [:]) throws -> (String, AsyncThrowingStream<MuxItem, Error>) {
        let id = UUID().uuidString
        var continuation: AsyncThrowingStream<MuxItem, Error>.Continuation!
        let stream = AsyncThrowingStream<MuxItem, Error>(bufferingPolicy: .unbounded) { continuation = $0 }
        lock.lock()
        guard open, socket != nil || link != nil else { lock.unlock(); throw DSHError("E_MUX_CLOSED") }
        let task = socket, remote = link
        streams[id] = continuation
        lock.unlock()
        continuation.onTermination = { [weak self] reason in
            if case .cancelled = reason { self?.cancel(streamId: id) }
        }
        if let remote {
            remote.open(streamId: id, endpoint: endpoint, args: args)
        } else if let task {
            try sendFrame(task, ["type": "open", "streamId": id, "endpoint": endpoint, "payload": ["args": args]])
        }
        return (id, stream)
    }

    public func cancel(streamId: String) {
        lock.lock()
        let task = socket, remote = link
        let removed = streams.removeValue(forKey: streamId) != nil
        lock.unlock()
        guard removed else { return }
        if let remote { remote.cancel(streamId: streamId) } else if let task { try? sendFrame(task, ["type": "cancel", "streamId": streamId]) }
    }

    public func close() {
        lock.lock()
        let task = socket, remote = link, pending = streams
        socket = nil; link = nil; streams = [:]; open = false
        lock.unlock()
        task?.cancel(with: .normalClosure, reason: nil)
        remote?.close()
        for (_, continuation) in pending { continuation.finish(throwing: DSHError("E_MUX_CLOSED")) }
    }

    private func sendFrame(_ task: URLSessionWebSocketTask, _ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        task.send(.string(String(decoding: data, as: UTF8.self))) { [weak self] error in
            if error != nil { self?.lost() }
        }
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.lost()
            case .success(let message):
                let data: Data
                switch message {
                case .string(let text): data = Data(text.utf8)
                case .data(let bytes): data = bytes
                @unknown default: data = Data()
                }
                if let frame = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { self.dispatch(frame) }
                self.receiveLoop(task)
            }
        }
    }

    private func dispatch(_ frame: [String: Any]) {
        guard let id = frame["streamId"] as? String else { return }
        lock.lock()
        if id == eventsStreamId {
            lock.unlock()
            if frame["type"] as? String == "item" {
                let value = frame["value"] as? [String: Any] ?? [:]
                if value["type"] as? String == "ready" {
                    lock.withLock { readyClientId = value["clientId"] as? String }
                    resolveReady(true)
                } else if let request = HostRequest.parse(value) {
                    client?.deliverHostRequest(request)
                }
            } else {
                // `$events` ending or failing invalidates the whole connection.
                resolveReady(false); lost()
            }
            return
        }
        let continuation = streams[id]
        let type = frame["type"] as? String
        if type == "end" || type == "error" { streams[id] = nil }
        lock.unlock()
        switch type {
        case "item":
            if let value = frame["value"] as? [String: Any] { continuation?.yield(MuxItem(value: value)) }
        case "end":
            continuation?.finish()
        case "error":
            let code = (frame["error"] as? [String: Any])?["code"] as? String ?? "E_MUX_STREAM"
            continuation?.finish(throwing: DSHError(code))
        default:
            break
        }
    }

    private func lost() {
        lock.lock()
        guard open else { lock.unlock(); return }
        open = false
        let pending = streams, task = socket, remote = link
        streams = [:]; socket = nil; link = nil
        lock.unlock()
        task?.cancel(with: .goingAway, reason: nil)
        remote?.close()
        resolveReady(false)
        for (_, continuation) in pending { continuation.finish(throwing: DSHError("E_MUX_LOST")) }
    }
}
