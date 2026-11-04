// SPDX-License-Identifier: AGPL-3.0-or-later
// Line-delimited JSON-RPC 2.0 MCP server; behaviour matches
// 原 Flutter 版 lib/phone_ios/mcp_server.dart (and Android McpServer.kt).
import Foundation

/// Cancelled when the relay connection that issued the call goes away.
public final class PhoneCallContext: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelledFlag = false
    private var listeners: [UUID: () -> Void] = [:]

    public init() {}
    public var cancelled: Bool { lock.withLock { cancelledFlag } }

    /// Returns a token to remove the listener.
    @discardableResult
    public func onCancel(_ listener: @escaping () -> Void) -> UUID {
        let id = UUID()
        let fireNow = lock.withLock { () -> Bool in
            if cancelledFlag { return true }
            listeners[id] = listener; return false
        }
        if fireNow { listener() }
        return id
    }
    public func removeListener(_ id: UUID) { lock.withLock { _ = listeners.removeValue(forKey: id) } }

    public func cancel() {
        let pending = lock.withLock { () -> [() -> Void] in
            if cancelledFlag { return [] }
            cancelledFlag = true
            let values = Array(listeners.values); listeners = [:]; return values
        }
        pending.forEach { $0() }
    }
}

public struct PhoneToolOutput: Sendable {
    public let text: String
    public let isError: Bool
    /// Runs after the reply line has been flushed to the relay (deferred app jumps).
    public let afterSend: (@Sendable () async -> Void)?
    public init(_ text: String, isError: Bool = false, afterSend: (@Sendable () async -> Void)? = nil) {
        self.text = text; self.isError = isError; self.afterSend = afterSend
    }
}

public struct McpReply: Sendable {
    public let line: String
    public let afterSend: (@Sendable () async -> Void)?
}

/// Arguments are JSONSerialization values; they are not mutated.
public struct ToolArguments: @unchecked Sendable {
    public let values: [String: Any]
}

public final class McpServer: Sendable {
    public typealias Call = @Sendable (String, ToolArguments, PhoneCallContext) async -> PhoneToolOutput
    static let versions = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]
    private let catalog: PhoneCatalog
    private let call: Call

    public init(catalog: PhoneCatalog, call: @escaping Call) {
        self.catalog = catalog; self.call = call
    }

    public func handle(_ line: String, context: PhoneCallContext = PhoneCallContext()) async -> McpReply? {
        if line.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        guard let raw = try? JSONSerialization.jsonObject(with: Data(line.utf8), options: [.fragmentsAllowed]) else {
            return McpReply(line: error(nil, -32700, "Parse error"), afterSend: nil)
        }
        guard let message = raw as? [String: Any] else { return McpReply(line: error(nil, -32600, "Invalid Request"), afterSend: nil) }
        let hasId = message.keys.contains("id")
        let id = message["id"]
        guard let method = message["method"] as? String else {
            let isResponse = message["result"] != nil || message["error"] != nil
            return hasId && !isResponse ? McpReply(line: error(id, -32600, "Invalid Request"), afterSend: nil) : nil
        }
        guard hasId else { return nil } // Notifications get no reply.
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String
            let version = requested.flatMap { Self.versions.contains($0) ? $0 : nil } ?? Self.versions.last!
            return McpReply(line: result(id, ["protocolVersion": version,
                                              "capabilities": ["tools": ["listChanged": false]],
                                              "serverInfo": ["name": "dsh-app-phone", "version": "1"]]), afterSend: nil)
        case "ping":
            return McpReply(line: result(id, [String: Any]()), afterSend: nil)
        case "tools/list":
            // Verbatim catalog text keeps tool definitions byte-stable.
            return McpReply(line: "{\"jsonrpc\":\"2.0\",\"id\":\(json(id)),\"result\":{\"tools\":\(catalog.raw)}}", afterSend: nil)
        case "tools/call":
            guard let name = params["name"] as? String else { return McpReply(line: error(id, -32602, "Invalid tool arguments"), afterSend: nil) }
            let input = params["arguments"] ?? [String: Any]()
            guard let args = input as? [String: Any] else { return McpReply(line: error(id, -32602, "Invalid tool arguments"), afterSend: nil) }
            guard catalog.valid(name, args) else {
                return McpReply(line: error(id, -32602, "Unknown tool or invalid arguments"), afterSend: nil)
            }
            let output = await call(name, ToolArguments(values: args), context)
            let body: [String: Any] = ["content": [["type": "text", "text": output.text]], "isError": output.isError]
            return McpReply(line: result(id, body), afterSend: output.afterSend)
        default:
            return McpReply(line: error(id, -32601, "Method not found"), afterSend: nil)
        }
    }

    private func json(_ value: Any?) -> String {
        guard let value, !(value is NSNull),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }
    private func result(_ id: Any?, _ value: Any) -> String {
        "{\"jsonrpc\":\"2.0\",\"id\":\(json(id)),\"result\":\(json(value))}"
    }
    private func error(_ id: Any?, _ code: Int, _ message: String) -> String {
        "{\"jsonrpc\":\"2.0\",\"id\":\(json(id)),\"error\":{\"code\":\(code),\"message\":\(json(message))}}"
    }
}
