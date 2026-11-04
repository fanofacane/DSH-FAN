// SPDX-License-Identifier: AGPL-3.0-or-later
// DSHCarrier over the ds-harness-remote tunnel (port of
// 原 Flutter 版 dsh_remote/lib/src/carrier/tunnel_carrier.dart; upstream MIT).
// Calls go through `harness.remote.call`, streams through
// `harness.remote.stream.*` events. Requests over 2 MiB and large responses or
// stream frames use the chunked `harness.remote.transfer.*` calls.
import DSHClient
import Foundation

struct RemoteHostSession: @unchecked Sendable {
    let rpc: RemoteRPCClient
    let capabilities: [String]
    let harnessVersion: String?
    var supportsTransfer: Bool { capabilities.contains("harness.remote.transfer.v1") }
    var supportsStreamTransfer: Bool { capabilities.contains("harness.remote.stream.transfer.v1") }
}

public final class RemoteTunnelCarrier: DSHCarrier, @unchecked Sendable {
    static let allowlist: Set<String> = [
        "$events", "$events/result", "agentPresets/list", "agentPresets/read", "agentPresets/select", "commands/execute",
        "commands/list", "credentials/describe", "credentials/set", "credentials/unset", "directoryPicker/list",
        "fileReferences/list", "goals/clear", "goals/complete", "goals/create", "goals/edit", "goals/pause", "goals/resume",
        "job/list", "job/follow", "llm/discoverModels", "llm/listConfigurableProviders", "llm/listProviders",
        "messageFeedback/delete", "messageFeedback/list", "messageFeedback/put", "pluginInventory/list",
        "pluginManager/listBundles", "pluginManager/listPlugins", "pluginManager/setBundleEnabled",
        "pluginManager/setPluginEnabled", "permissionPresets/catalog", "schedule/list", "schedule/catalog",
        "schedule/history", "schedule/update", "schedule/delete", "session/attachment", "session/cancel",
        "session/canOpenWorkspacePath", "session/control", "session/create", "session/follow", "session/fork",
        "session/list", "session/modelCatalog", "session/page", "session/prompt", "remoteAccess/follow",
        "session/projections", "session/initializeDefaultModel", "session/workspacePathApplications", "session/rename",
        "session/search", "session/selectModel", "session/updateQueue", "sessionReferenceResolver/candidates",
        "settings/describe", "settings/mutate", "settings/replace", "settings/update", "skills/list",
        "subagents/interruptByParent", "subagents/list", "subagents/prompt", "userQuestions/answer",
        "userQuestions/attachWait", "claudeCodeMods/watchBand", "claudeCodeMods/pressBand", "workspaceFiles/list",
        "workspaceFiles/stat", "workspaceFiles/read", "workspaceFiles/readBytes", "workspaceFiles/readAll",
        "workspaceFiles/readRelated", "workspaceFiles/changes", "officeToPdf/render", "officeToPdf/generation",
        "workspace/archiveSession", "workspace/create", "workspace/delete", "workspace/follow", "workspace/insertBefore",
        "workspace/insertSessionBefore", "workspace/rename", "workspace/unarchiveSession", "workspace/initializeDefault",
        "workspace/pinSession", "workspace/unpinSession", "terminal/environment", "terminal/shells", "terminal/list",
        "terminal/create", "terminal/write", "terminal/resize", "terminal/rename", "terminal/close", "terminal/follow",
        "terminal/retain",
    ]
    static let directCallBytes = 2 * 1024 * 1024
    static let transferChunk = 512 * 1024
    static let maxTransfer = 288 * 1024 * 1024

    public let hostId: String
    private let opener: @Sendable (RemoteFailure?) async throws -> RemoteHostSession
    private let lock = NSLock()
    private var session: RemoteHostSession?
    private var opening: Task<RemoteHostSession, Error>?
    private var health: Task<Void, Never>?
    private var closed = false
    /// The last failure; a non-retryable one sticks until `reconnect()`.
    public private(set) var lastFailure: RemoteFailure?
    /// Called on every connection failure (main-thread hop is the caller's job).
    public var onFailure: (@Sendable (RemoteFailure) -> Void)?

    init(hostId: String, opener: @escaping @Sendable (RemoteFailure?) async throws -> RemoteHostSession) {
        self.hostId = hostId
        self.opener = opener
    }

    func start() async throws { _ = try await ensureSession() }

    public var hostVersion: String? { lock.withLock { session?.harnessVersion } }
    /// A live encrypted session is open (it reopens on the next call otherwise).
    public var isConnected: Bool { lock.withLock { session.map { !$0.rpc.isClosed } ?? false } }

    public func reconnect() {
        let current = lock.withLock { () -> RemoteHostSession? in lastFailure = nil; defer { session = nil }; return session }
        current?.rpc.close()
    }

    private func ensureSession() async throws -> RemoteHostSession {
        let (current, pending, sticky): (RemoteHostSession?, Task<RemoteHostSession, Error>?, RemoteFailure?) = lock.withLock {
            if closed { return (nil, nil, RemoteFailure("CLIENT_CLOSED", "The remote carrier is closed.", retryable: false)) }
            if let session, !session.rpc.isClosed { return (session, nil, nil) }
            if let failure = lastFailure, !failure.retryable { return (nil, nil, failure) }
            if let opening { return (nil, opening, nil) }
            let previous = lastFailure
            let task = Task { try await self.opener(previous) }
            opening = task
            return (nil, task, nil)
        }
        if let sticky { throw DSHError(sticky.code) }
        if let current { return current }
        do {
            let fresh = try await pending!.value
            let keep = lock.withLock { () -> Bool in
                opening = nil
                guard !closed else { return false }
                session = fresh; lastFailure = nil
                return true
            }
            guard keep else { fresh.rpc.close(); throw DSHError("CLIENT_CLOSED") }
            fresh.rpc.onDone { [weak self] reason in self?.sessionEnded(fresh, reason) }
            startHealth(fresh)
            return fresh
        } catch let failure as RemoteFailure {
            lock.withLock { opening = nil }
            record(failure)
            throw DSHError(failure.code)
        } catch {
            lock.withLock { opening = nil }
            throw error
        }
    }

    private func sessionEnded(_ ended: RemoteHostSession, _ reason: RemoteFailure) {
        let current = lock.withLock { () -> Bool in
            guard session?.rpc === ended.rpc else { return false }
            session = nil
            return true
        }
        guard current else { return }
        health?.cancel()
        if reason.code != "CLIENT_CLOSED" { record(reason) }
    }

    private func record(_ failure: RemoteFailure) {
        lock.withLock { lastFailure = failure }
        onFailure?(failure)
    }

    /// `harness.transport.describe` when nothing has arrived for 25 s.
    private func startHealth(_ watched: RemoteHostSession) {
        health?.cancel()
        health = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard let self, !Task.isCancelled, !watched.rpc.isClosed else { return }
                guard watched.rpc.sinceInbound >= 25 else { continue }
                do { _ = try await watched.rpc.call("harness.transport.describe", timeout: 10) } catch let error as RemoteRPCError where error.isLocal {
                    self.record(RemoteFailure("CONNECTION_FAILED", "Health check failed: \(error.message)", retryable: true))
                    watched.rpc.close()
                    return
                } catch {}
            }
        }
    }

    public func close() {
        let current = lock.withLock { () -> RemoteHostSession? in
            closed = true
            defer { session = nil }
            return session
        }
        health?.cancel()
        opening?.cancel()
        current?.rpc.close()
    }

    // MARK: Calls

    public func call(_ endpoint: String, args: [String: Any]) async throws -> Any? {
        guard Self.allowlist.contains(endpoint) else { throw DSHError("METHOD_NOT_ALLOWED") }
        let session = try await ensureSession()
        let request: [String: Any] = ["endpoint": endpoint, "payload": ["args": args]]
        let encoded = Data(RemoteBytes.encodeJSON(request).utf8)
        let response: Any?
        do {
            if encoded.count > Self.directCallBytes {
                response = try await transferred(session, endpoint: endpoint, encoded: encoded)
            } else {
                do { response = try await session.rpc.call("harness.remote.call", request, timeout: 65) } catch let error as RemoteRPCError
                    where !error.isLocal && error.code == "RESPONSE_TOO_LARGE" {
                    response = try await transferred(session, endpoint: endpoint, encoded: encoded)
                }
            }
        } catch let error as RemoteRPCError {
            // A local failure (timeout, lost tunnel) means the outcome is unknown.
            if error.isLocal, error.code != "FRAME_TOO_LARGE", error.code != "RATE_LIMITED" {
                throw DSHError(error.code == "RPC_TIMEOUT" ? "E_REMOTE_TIMEOUT" : "E_REMOTE_LOST")
            }
            throw DSHError(error.code)
        }
        guard let map = response as? [String: Any] else { throw DSHError("E_RPC_ENVELOPE") }
        if map["ok"] as? Bool == true { return map["value"] }
        if let error = map["error"] as? [String: Any], let code = error["code"] as? String { throw DSHError(code) }
        throw DSHError("E_RPC_ENVELOPE")
    }

    private func transferred(_ session: RemoteHostSession, endpoint: String, encoded: Data) async throws -> Any? {
        guard session.supportsTransfer, encoded.count <= Self.maxTransfer else {
            throw RemoteRPCError(code: "FRAME_TOO_LARGE", message: "\(endpoint) is too large for this Host.", isLocal: true)
        }
        let rpc = session.rpc
        let id = RemoteBytes.uuidV7()
        let chunks = (encoded.count + Self.transferChunk - 1) / Self.transferChunk
        _ = try await rpc.call("harness.remote.transfer.open", ["transferId": id, "totalBytes": encoded.count, "totalChunks": chunks], timeout: 65)
        defer { Task { _ = try? await rpc.call("harness.remote.transfer.close", ["transferId": id], timeout: 5) } }
        for index in 0..<chunks {
            let start = index * Self.transferChunk
            let piece = encoded.subdata(in: start..<min(start + Self.transferChunk, encoded.count))
            _ = try await rpc.call("harness.remote.transfer.chunk",
                                   ["transferId": id, "index": index, "data": piece.base64EncodedString()], timeout: 65)
        }
        let committed = try await rpc.call("harness.remote.transfer.commit", ["transferId": id], timeout: 65) as? [String: Any] ?? [:]
        if committed["kind"] as? String == "inline" { return committed["response"] }
        guard committed["kind"] as? String == "chunked", committed["transferId"] as? String == id,
              let total = committed["totalBytes"] as? Int, let count = committed["totalChunks"] as? Int else {
            throw DSHError("E_REMOTE_TRANSFER")
        }
        let bytes = try await read(rpc, transferId: id, totalBytes: total, totalChunks: count)
        guard let value = try? JSONSerialization.jsonObject(with: bytes, options: .fragmentsAllowed) else { throw DSHError("E_REMOTE_TRANSFER") }
        return value
    }

    func read(_ rpc: RemoteRPCClient, transferId: String, totalBytes: Int, totalChunks: Int) async throws -> Data {
        guard totalBytes > 0, totalBytes <= Self.maxTransfer,
              totalChunks == (totalBytes + Self.transferChunk - 1) / Self.transferChunk else { throw DSHError("E_REMOTE_TRANSFER") }
        var out = Data()
        for index in 0..<totalChunks {
            let chunk = try await rpc.call("harness.remote.transfer.read", ["transferId": transferId, "index": index], timeout: 65) as? [String: Any]
            let expected = min(totalBytes - index * Self.transferChunk, Self.transferChunk)
            guard chunk?["transferId"] as? String == transferId, chunk?["index"] as? Int == index,
                  let text = chunk?["data"] as? String, let piece = Data(base64Encoded: text), piece.count == expected else {
                throw DSHError("E_REMOTE_TRANSFER")
            }
            out.append(piece)
        }
        return out
    }

    // MARK: Streams

    public func openLink(onFrame: @escaping @Sendable ([String: Any]) -> Void,
                         onLost: @escaping @Sendable () -> Void) async throws -> DSHMuxLink {
        let session = try await ensureSession()
        let link = TunnelLink(carrier: self, session: session, onFrame: onFrame, onLost: onLost)
        link.start()
        return link
    }

    fileprivate func closeSession(_ ended: RemoteHostSession) {
        let current = lock.withLock { () -> Bool in
            guard session?.rpc === ended.rpc else { return false }
            session = nil
            return true
        }
        if current { health?.cancel() }
        ended.rpc.close()
    }
}

private final class TunnelLink: DSHMuxLink, @unchecked Sendable {
    private weak var carrier: RemoteTunnelCarrier?
    private let session: RemoteHostSession
    private let onFrame: @Sendable ([String: Any]) -> Void
    private let onLost: @Sendable () -> Void
    private let lock = NSLock()
    private var streams = Set<String>()
    /// Per-stream ordering for frames that need an async transfer read.
    private var chains: [String: Task<Void, Never>] = [:]
    private var eventHandler: UUID?
    private var closed = false

    init(carrier: RemoteTunnelCarrier, session: RemoteHostSession,
         onFrame: @escaping @Sendable ([String: Any]) -> Void, onLost: @escaping @Sendable () -> Void) {
        self.carrier = carrier; self.session = session; self.onFrame = onFrame; self.onLost = onLost
    }

    func start() {
        eventHandler = session.rpc.onEvent { [weak self] event in self?.queue(event) }
        session.rpc.onDone { [weak self] _ in self?.lose() }
    }

    private func lose() {
        let first = lock.withLock { () -> Bool in defer { closed = true }; return !closed }
        if first { onLost() }
    }

    private func emit(_ frame: [String: Any]) {
        guard !lock.withLock({ closed }) else { return }
        onFrame(frame)
    }

    private func queue(_ event: RemoteRPCClient.Event) {
        guard let data = event.data as? [String: Any], let id = data["streamId"] as? String else { return }
        let task: Task<Void, Never>? = lock.withLock {
            guard !closed, streams.contains(id) else { return nil }
            let previous = chains[id]
            let next = Task { [weak self] in
                await previous?.value
                await self?.handle(event.name, id, data)
            }
            chains[id] = next
            return next
        }
        _ = task
    }

    private func handle(_ name: String, _ id: String, _ data: [String: Any]) async {
        guard lock.withLock({ !closed && streams.contains(id) }) else { return }
        switch name {
        case "harness.remote.frame":
            guard data["hasValue"] as? Bool == true else { return }
            var frame = data
            if data["transfer"] != nil {
                do { frame = try await readFrame(id, data) } catch {
                    guard lock.withLock({ streams.remove(id) != nil }) else { return }
                    closeRemote(id)
                    emit(["type": "error", "streamId": id, "error": ["code": "INVALID_MESSAGE", "message": "Remote stream transfer failed."]])
                    return
                }
            }
            guard lock.withLock({ streams.contains(id) }) else { return }
            emit(["type": "item", "streamId": id, "value": frame["value"] ?? NSNull()])
        case "harness.remote.stream.closed":
            lock.withLock { _ = streams.remove(id); chains[id] = nil }
            switch data["reason"] as? String {
            case "failed":
                let failure = data["failure"] as? [String: Any] ?? [:]
                emit(["type": "error", "streamId": id,
                      "error": ["code": failure["code"] as? String ?? "internal", "message": failure["message"] as? String ?? ""]])
            case "peer-disconnected":
                lose()
                carrier?.closeSession(session)
            default:
                emit(["type": "end", "streamId": id])
            }
        default:
            break
        }
    }

    private func readFrame(_ id: String, _ data: [String: Any]) async throws -> [String: Any] {
        guard session.supportsStreamTransfer, data["value"] == nil, let descriptor = data["transfer"] as? [String: Any],
              descriptor["kind"] as? String == "chunked", let transferId = descriptor["transferId"] as? String,
              let bytes = descriptor["totalBytes"] as? Int, let chunks = descriptor["totalChunks"] as? Int,
              let carrier else { throw DSHError("E_REMOTE_TRANSFER") }
        defer { Task { [rpc = session.rpc] in _ = try? await rpc.call("harness.remote.transfer.close", ["transferId": transferId], timeout: 5) } }
        let raw = try await carrier.read(session.rpc, transferId: transferId, totalBytes: bytes, totalChunks: chunks)
        guard let frame = try JSONSerialization.jsonObject(with: raw) as? [String: Any], frame["streamId"] as? String == id,
              frame["hasValue"] as? Bool == true, frame["transfer"] == nil else { throw DSHError("E_REMOTE_TRANSFER") }
        return frame
    }

    func open(streamId: String, endpoint: String, args: [String: Any]) {
        guard !lock.withLock({ closed }) else { return }
        guard RemoteTunnelCarrier.allowlist.contains(endpoint) else {
            DispatchQueue.global().async { [weak self] in
                self?.emit(["type": "error", "streamId": streamId, "error": ["code": "METHOD_NOT_ALLOWED", "message": endpoint]])
            }
            return
        }
        lock.withLock { _ = streams.insert(streamId) }
        var params: [String: Any] = ["streamId": streamId, "endpoint": endpoint, "payload": ["args": args]]
        if session.supportsStreamTransfer { params["transferFrames"] = true }
        let rpc = session.rpc
        Task { [weak self] in
            do { _ = try await rpc.call("harness.remote.stream.open", params, timeout: 15) } catch {
                guard let self, self.lock.withLock({ self.streams.remove(streamId) != nil }) else { return }
                if let error = error as? RemoteRPCError, error.isTransportClosed { return }
                self.closeRemote(streamId)
                let code = (error as? RemoteRPCError)?.code ?? "internal"
                self.emit(["type": "error", "streamId": streamId, "error": ["code": code, "message": "\(error)"]])
            }
        }
    }

    private func closeRemote(_ id: String) {
        let rpc = session.rpc
        guard !rpc.isClosed else { return }
        Task { _ = try? await rpc.call("harness.remote.stream.close", ["streamId": id], timeout: 15) }
    }

    func cancel(streamId: String) {
        guard lock.withLock({ streams.remove(streamId) != nil }) else { return }
        closeRemote(streamId)
    }

    func close() {
        let first = lock.withLock { () -> Bool in defer { closed = true }; return !closed }
        guard first else { return }
        if let eventHandler { session.rpc.removeEventHandler(eventHandler) }
        carrier?.closeSession(session)
    }
}
