// SPDX-License-Identifier: AGPL-3.0-or-later
// Durable session log events (subset used by the chat transcript), mirroring
// SessionLogEvent / Message / Part in 原 Flutter 版 dsh_client/lib/src/models.dart.
import Foundation

public struct ToolCall: Sendable, Equatable {
    public let id: String
    public let name: String
    public let arguments: String
}

public struct MessageImageReference: Sendable, Equatable, Hashable {
    public let attachmentId: String?
    public let data: Data?
    public init?(_ part: [String: Any]) {
        attachmentId = (part["attachment"] as? [String: Any])?["attachmentId"] as? String
        data = (part["data"] as? String).flatMap { Data(base64Encoded: $0) }
        if attachmentId == nil && data == nil { return nil }
    }
}

public struct LogMessage: Sendable, Equatable {
    public let text: String
    public let reasoning: String
    public let toolCalls: [ToolCall]
    public let imageCount: Int
    public let images: [MessageImageReference]
    /// `user` for what the person typed; other kinds are injected context.
    public let sourceKind: String
    /// `session/prompt` requestId, for matching the optimistic echo.
    public let requestId: String?
    public let toolCallId: String?
    public let isError: Bool

    init(_ json: Any?) {
        let map = json as? [String: Any] ?? [:]
        var text = "", reasoning = "", calls: [ToolCall] = [], images = 0
        var references: [MessageImageReference] = []
        for part in map["content"] as? [[String: Any]] ?? [] {
            switch part["type"] as? String {
            case "text": text += part["text"] as? String ?? ""
            case "reasoning": reasoning += part["text"] as? String ?? ""
            case "image":
                images += 1
                if let reference = MessageImageReference(part) { references.append(reference) }
            case "tool-call":
                calls.append(ToolCall(id: part["id"] as? String ?? "", name: part["name"] as? String ?? "",
                                      arguments: part["arguments"] as? String ?? ""))
            default: break
            }
        }
        self.text = text; self.reasoning = reasoning; toolCalls = calls; imageCount = images; self.images = references
        let source = map["source"] as? [String: Any]
        sourceKind = source?["kind"] as? String ?? "unknown"
        requestId = source?["rpcId"] as? String
        toolCallId = map["toolCallId"] as? String
        isError = map["isError"] as? Bool == true
    }
}

public enum LogEvent: Sendable, Equatable {
    case userMessage(seq: Int, LogMessage)
    case assistantMessage(seq: Int, turn: Int, step: Int, LogMessage, interrupted: Bool)
    case toolResult(seq: Int, callId: String, text: String, failed: Bool, presentation: ToolPresentation)
    case turnStarted(seq: Int, turn: Int)
    case turnEnded(seq: Int, turn: Int, reason: String)
    case attempt(seq: Int)
    /// `llm/retry`: the provider failed and DSH will try again (`code`: SERVER,
    /// RATE_LIMIT, TIMEOUT, TRANSPORT, EMPTY_RESPONSE).
    case retry(seq: Int, retry: Int, maxRetries: Int?, code: String)
    case other(seq: Int, type: String)

    public var seq: Int {
        switch self {
        case .userMessage(let s, _), .assistantMessage(let s, _, _, _, _), .toolResult(let s, _, _, _, _),
             .turnStarted(let s, _), .turnEnded(let s, _, _), .attempt(let s), .retry(let s, _, _, _),
             .other(let s, _): return s
        }
    }

    static func parse(_ json: Any?) -> LogEvent? {
        guard let map = json as? [String: Any], let type = map["type"] as? String else { return nil }
        let seq = map["seq"] as? Int ?? -1
        let data = map["data"] as? [String: Any] ?? [:]
        let turn = data["turn"] as? Int ?? 0
        switch type {
        case "user/message":
            return .userMessage(seq: seq, LogMessage(data))
        case "assistant/message":
            return .assistantMessage(seq: seq, turn: turn, step: data["step"] as? Int ?? 0,
                                     LogMessage(data["message"]), interrupted: data["interrupted"] as? Bool == true)
        case "tool/result":
            let message = LogMessage(data["message"])
            let callId = message.toolCallId ?? data["callId"] as? String ?? ""
            let hasError = data["error"].map { !($0 is NSNull) } ?? false
            return .toolResult(seq: seq, callId: callId, text: message.text,
                               failed: hasError || message.isError, presentation: ToolPresentation(data["meta"]))
        case "turn/start":
            return .turnStarted(seq: seq, turn: turn)
        case "turn/end":
            // completed / aborted / blocked / error / max-tokens / interrupted / forked.
            let reason = data["reason"] as? [String: Any]
            var kind = reason?["kind"] as? String ?? "unknown"
            if kind == "error", let failure = reason?["error"] as? [String: Any] {
                kind = failure["kind"] as? String ?? failure["code"] as? String ?? kind
            }
            return .turnEnded(seq: seq, turn: turn, reason: kind)
        case "assistant/attempt":
            return .attempt(seq: seq)
        case "llm/retry":
            let failure = data["failure"] as? [String: Any]
            return .retry(seq: seq, retry: data["retry"] as? Int ?? 1, maxRetries: data["maxRetries"] as? Int,
                          code: failure?["code"] as? String ?? "SERVER")
        default:
            return .other(seq: seq, type: type)
        }
    }
}

public struct SessionSummary: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String?
    public let updatedAt: Date
    public let running: Bool
    public let blank: Bool
    public let agentAvailable: Bool
    public let cwd: String?

    public init(id: String, title: String?, updatedAt: Date, running: Bool, blank: Bool, agentAvailable: Bool, cwd: String? = nil) {
        self.id = id; self.title = title; self.updatedAt = updatedAt
        self.running = running; self.blank = blank; self.agentAvailable = agentAvailable
        self.cwd = cwd
    }
}

/// An image attached to a prompt (`{type: image, mediaType, data, name}`).
public struct PromptImage: Sendable {
    public let mediaType: String
    public let data: Data
    public let name: String?
    public init(mediaType: String, data: Data, name: String? = nil) {
        self.mediaType = mediaType; self.data = data; self.name = name
    }
}
