// SPDX-License-Identifier: AGPL-3.0-or-later
// Swift port of the 原 Flutter 版 dsh_client wire contract: launch-token login,
// JSON RPC envelope over HTTP, and the multiplexed WebSocket (MuxConnection).
import Foundation

public struct DSHError: Error, Equatable, Sendable {
    /// Stable code: a DSH error code (e.g. `credential/rejected`), an
    /// `URL_ERROR_<n>`, or one of the client's own `E_*` codes.
    public let code: String
    public init(_ code: String) { self.code = code }
}

public struct ReasoningEffort: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
}

public struct ModelOption: Identifiable, Hashable, Sendable {
    public let provider: String
    public let model: String
    public let name: String
    /// Selectable reasoning efforts (`off`, `low`, `high`, `max` for DeepSeek).
    public var efforts: [ReasoningEffort] = []
    public var defaultEffort: String?
    public var id: String { provider + "/" + model }
    public static func == (a: ModelOption, b: ModelOption) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public struct ModelCatalog: Sendable {
    public let models: [ModelOption]
    public let defaultModel: ModelOption?
}

public struct CredentialState: Sendable {
    public let configured: Bool
    public let writable: Bool
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// One authenticated connection to a local `dsh web`. Holds the auth cookie in
/// memory only; nothing is written to disk.
public final class DSHClient: @unchecked Sendable {
    public static let deepSeekKeyRef = "DEEPSEEK_API_KEY"

    let baseURL: URL
    let session: URLSession
    private let delegate = NoRedirect()
    private let lock = NSLock()
    private var cookie = ""
    private var mux: MuxConnection?
    private var hostHandler: (@Sendable (HostRequest) -> Void)?

    /// Approvals and questions from `$events` (all sessions). Pending ones are
    /// redelivered whenever the mux reconnects.
    public func setHostRequestHandler(_ handler: (@Sendable (HostRequest) -> Void)?) {
        lock.withLock { hostHandler = handler }
    }
    func deliverHostRequest(_ request: HostRequest) {
        let handler = lock.withLock { hostHandler }
        handler?(request)
    }

    /// Set for a remote tunnel; nil for a direct `dsh web` over HTTP.
    public let carrier: DSHCarrier?

    /// A client whose RPCs and streams travel through `carrier` (remote relay).
    public convenience init(carrier: DSHCarrier) {
        self.init(baseURL: URL(string: "http://remote.invalid")!, carrier: carrier)
    }

    public init(baseURL: URL, carrier: DSHCarrier? = nil) {
        self.baseURL = baseURL
        self.carrier = carrier
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 600
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }

    var authCookie: String { lock.lock(); defer { lock.unlock() }; return cookie }
    var origin: String { "\(baseURL.scheme ?? "http")://\(baseURL.host ?? "127.0.0.1"):\(baseURL.port ?? 80)" }

    /// Exchanges the one-time launch token for the `dsh-auth-*` cookie.
    public func login(token: String) async throws {
        if carrier != nil { return } // The tunnel is already authenticated end to end.
        var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        parts.path = "/"
        parts.queryItems = [URLQueryItem(name: "token", value: token)]
        var request = URLRequest(url: parts.url!)
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let response = try await send(request).1
        guard [302, 303].contains(response.statusCode),
              let header = response.value(forHTTPHeaderField: "Set-Cookie"),
              let parsed = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": header], for: baseURL)
                .first(where: { $0.name.hasPrefix("dsh-auth-") }) else {
            throw DSHError("E_LOGIN_REFUSED")
        }
        lock.withLock { cookie = parsed.name + "=" + parsed.value }
    }

    /// `POST /api/<method>` with the client-request envelope; returns `result.value`.
    @discardableResult
    public func rpc(_ method: String, _ args: [String: Any] = [:]) async throws -> Any? {
        if let carrier { return try await carrier.call(method, args: args) }
        var request = URLRequest(url: baseURL.appendingPathComponent("api").appendingPathComponent(method))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authCookie, forHTTPHeaderField: "Cookie")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        // The engine's Node server drops idle keep-alive sockets after 5 s and
        // URLSession does not retry a POST on a reused dead socket (-1005).
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let rpcId = UUID().uuidString
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": "client-request", "rpcId": rpcId, "method": method, "payload": ["args": args],
        ])
        let (data, response) = try await send(request)
        if response.statusCode == 401 || response.statusCode == 403 { throw DSHError("E_UNAUTHORIZED") }
        guard response.statusCode == 200 else { throw DSHError("E_RPC_ENVELOPE") }
        let envelope: [String: Any]
        if let type = response.value(forHTTPHeaderField: "Content-Type"), type.lowercased().hasPrefix("multipart/form-data") {
            do { envelope = try BinaryRPC.decode(data, contentType: type) } catch { throw DSHError("E_RPC_BINARY") }
        } else {
            guard let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DSHError("E_RPC_ENVELOPE") }
            envelope = decoded
        }
        guard envelope["type"] as? String == "server-response", envelope["rpcId"] as? String == rpcId,
              let result = envelope["result"] as? [String: Any] else { throw DSHError("E_RPC_ENVELOPE") }
        guard result["ok"] as? Bool == true else {
            let code = (result["error"] as? [String: Any])?["code"] as? String
            throw DSHError(code ?? "E_RPC_REFUSED")
        }
        return result["value"]
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw DSHError("E_TRANSPORT") }
            return (data, http)
        } catch let error as DSHError {
            throw error
        } catch {
            let ns = error as NSError
            throw DSHError(ns.domain == NSURLErrorDomain ? "URL_ERROR_\(ns.code)" : "E_TRANSPORT")
        }
    }

    // MARK: Mux

    /// The shared WebSocket; opened on first use and reopened after a loss.
    public func muxConnection() async throws -> MuxConnection {
        let (existing, created): (MuxConnection?, MuxConnection?) = lock.withLock {
            if let current = mux, current.isOpen { return (current, nil) }
            let fresh = MuxConnection(client: self)
            mux = fresh
            return (nil, fresh)
        }
        if let existing { return existing }
        guard let created else { throw DSHError("E_MUX_CLOSED") }
        try await created.connect()
        return created
    }

    public func close() {
        let current: MuxConnection? = lock.withLock { let value = mux; mux = nil; return value }
        current?.close()
        carrier?.close()
    }

    // MARK: Credentials and models

    public func credentialState(ref: String = deepSeekKeyRef) async throws -> CredentialState {
        let value = try await rpc("credentials/describe", ["refs": [ref]]) as? [String: Any]
        let row = value?[ref] as? [String: Any]
        return CredentialState(configured: row?["configured"] as? Bool == true, writable: row?["writable"] as? Bool == true)
    }

    /// Stores the key inside the engine (`$DSH_HOME/.credentials.yaml`); the app keeps no copy.
    public func setProviderKey(_ key: String, ref: String = deepSeekKeyRef) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DSHError("E_EMPTY_KEY") }
        try await rpc("credentials/set", ["ref": ref, "value": trimmed])
    }

    public func clearProviderKey(ref: String = deepSeekKeyRef) async throws {
        try await rpc("credentials/unset", ["ref": ref])
    }

    /// Lists only providers with a usable credential (empty before a key is set).
    public func modelCatalog() async throws -> ModelCatalog {
        let value = try await rpc("session/modelCatalog") as? [String: Any] ?? [:]
        var models: [ModelOption] = []
        for group in value["groups"] as? [[String: Any]] ?? [] {
            let provider = group["id"] as? String ?? ""
            for model in group["models"] as? [[String: Any]] ?? [] {
                guard let id = model["id"] as? String, !id.isEmpty else { continue }
                let reasoning = model["reasoning"] as? [String: Any]
                let efforts = (reasoning?["efforts"] as? [[String: Any]] ?? []).compactMap { effort -> ReasoningEffort? in
                    guard let value = effort["id"] as? String else { return nil }
                    return ReasoningEffort(id: value, name: effort["name"] as? String ?? value)
                }
                models.append(ModelOption(provider: provider, model: id, name: model["name"] as? String ?? id,
                                          efforts: efforts, defaultEffort: reasoning?["defaultEffort"] as? String))
            }
        }
        var fallback: ModelOption?
        if let selection = value["default"] as? [String: Any],
           let provider = selection["provider"] as? String, let model = selection["model"] as? String {
            fallback = models.first { $0.provider == provider && $0.model == model }
                ?? ModelOption(provider: provider, model: model, name: model)
        }
        return ModelCatalog(models: models, defaultModel: fallback)
    }

    // MARK: Sessions

    /// `session/list`, newest first; subagent children and blank sessions are dropped.
    public func listSessions() async throws -> [SessionSummary] {
        let value = try await rpc("session/list", ["_request": [String: Any]()]) as? [String: Any]
        return (value?["items"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["sessionId"] as? String, !id.isEmpty,
                  item["parentSessionId"] == nil || item["parentSessionId"] is NSNull,
                  item["origin"] as? String != "subagent" else { return nil }
            let projections = (item["projections"] as? [String: Any])?["values"] as? [String: Any]
            let millis = (item["updatedAt"] as? NSNumber)?.doubleValue ?? 0
            return SessionSummary(id: id, title: projections?["title"] as? String,
                                  updatedAt: Date(timeIntervalSince1970: millis / 1000),
                                  running: item["running"] as? Bool == true, blank: item["blank"] as? Bool == true,
                                  agentAvailable: item["agentAvailable"] as? Bool == true,
                                  cwd: item["cwd"] as? String)
        }
    }

    /// `session/create`; pass `resume` to reload a stored session into the Host.
    public func createSession(cwd: String? = nil, workspaceId: String? = nil, agentPreset: String? = nil, resume sessionId: String? = nil) async throws -> String {
        var request: [String: Any] = [:]
        if let cwd { request["cwd"] = cwd }
        if let workspaceId { request["workspaceId"] = workspaceId }
        if let agentPreset { request["agentPreset"] = agentPreset }
        if let sessionId { request["sessionId"] = sessionId }
        let value = try await rpc("session/create", ["request": request]) as? [String: Any]
        guard let id = value?["sessionId"] as? String, !id.isEmpty else { throw DSHError("E_SESSION_CREATE") }
        return id
    }

    public func selectModel(sessionId: String, model: ModelOption, reasoningEffort: String? = nil) async throws {
        var request: [String: Any] = ["sessionId": sessionId, "provider": model.provider, "model": model.model]
        if let reasoningEffort { request["reasoningEffort"] = reasoningEffort }
        try await rpc("session/selectModel", ["request": request])
    }

    /// Queues a user message. Pair with `follow(sessionId:)` to read the reply.
    @discardableResult
    public func prompt(sessionId: String, text: String, images: [PromptImage] = [],
                       requestId: String = UUID().uuidString) async throws -> String {
        var content: [[String: Any]] = []
        if !text.isEmpty { content.append(["type": "text", "text": text]) }
        for image in images {
            var part: [String: Any] = ["type": "image", "mediaType": image.mediaType, "data": image.data.base64EncodedString()]
            if let name = image.name { part["name"] = name }
            content.append(part)
        }
        guard !content.isEmpty else { throw DSHError("E_EMPTY_PROMPT") }
        try await rpc("session/prompt", ["request": [
            "requestId": requestId, "sessionId": sessionId, "mode": "queue",
            "content": content, "clientTimeZone": TimeZone.current.identifier,
        ]])
        return requestId
    }

    /// Next model the session will use (its own selection, else the last used one).
    public func sessionModel(_ sessionId: String) async throws -> (provider: String, model: String)? {
        let list = try await rpc("session/list", ["_request": [String: Any]()]) as? [String: Any]
        let item = (list?["items"] as? [[String: Any]])?.first { $0["sessionId"] as? String == sessionId }
        let selection = ((item?["projections"] as? [String: Any])?["values"] as? [String: Any])?["modelSelection"] as? [String: Any]
        let chosen = (selection?["next"] ?? selection?["lastUsed"]) as? [String: Any]
        guard let provider = chosen?["provider"] as? String, let model = chosen?["model"] as? String else { return nil }
        return (provider, model)
    }

    public func cancel(sessionId: String) async throws {
        try await rpc("session/cancel", ["request": ["sessionId": sessionId]])
    }
}
