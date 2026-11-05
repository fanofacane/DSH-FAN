// SPDX-License-Identifier: AGPL-3.0-or-later
// `session/follow` decoded into the events a chat view needs.
import Foundation

public enum ChatEvent: Sendable, Equatable {
    /// First frame: the recent durable history. Prompts sent after this are observed.
    case snapshot([LogEvent], hasMore: Bool)
    case timeline([RunFact], replace: Bool)
    /// A durable event appended to the session log.
    case event(LogEvent)
    case textDelta(String)
    case reasoningDelta(String)
    case toolCallDelta(id: String, name: String?, argumentsDelta: String)
    /// A model call finished with a failure (e.g. `auth`, `rate-limit`).
    case modelFailure(String)
}

extension DSHClient {
    /// Follows one session with assistant streaming. Cancel the consuming task to stop.
    public func follow(sessionId: String) async throws -> AsyncThrowingStream<ChatEvent, Error> {
        try await follow(address: ["kind": "session", "sessionId": sessionId])
    }

    /// A child is always addressed through its owning parent.
    public func follow(address: [String: Any]) async throws -> AsyncThrowingStream<ChatEvent, Error> {
        let mux = try await muxConnection()
        let (_, frames) = try mux.open(endpoint: "session/follow", args: ["request": [
            "address": address, "assistantStream": true,
        ]])
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await item in frames {
                        for event in Self.decode(item.value) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    #if DEBUG
    public static func decodeFollowFixture(_ data: Data) -> [ChatEvent] {
        guard let frame = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        return decode(frame)
    }
    #endif

    static func decode(_ value: [String: Any]) -> [ChatEvent] {
        switch value["type"] as? String {
        case "snapshot":
            let raw = value["records"] as? [[String: Any]] ?? []
            let decoded = raw.compactMap { frame -> (LogEvent, RunFact?)? in
                let event = frame["event"]
                guard let record = LogEvent.parse(event) else { return nil }
                return (record, RunFact(event, log: record))
            }
            let records = decoded.map(\.0)
            return [.timeline(decoded.compactMap(\.1), replace: true),
                    .snapshot(records, hasMore: value["hasMore"] as? Bool == true)]
        case "assistant-stream":
            guard let frame = value["frame"] as? [String: Any], frame["type"] as? String == "chunk",
                  let chunk = frame["chunk"] as? [String: Any] else { return [] }
            switch chunk["type"] as? String {
            case "text-delta":
                if let text = chunk["text"] as? String, !text.isEmpty { return [.textDelta(text)] }
            case "reasoning-delta":
                if let text = chunk["text"] as? String, !text.isEmpty { return [.reasoningDelta(text)] }
            case "tool-call-delta":
                return [.toolCallDelta(id: chunk["id"] as? String ?? "", name: chunk["name"] as? String,
                                       argumentsDelta: chunk["argumentsDelta"] as? String ?? "")]
            case "finish":
                let reason = chunk["reason"] as? [String: Any]
                if let failure = reason?["failure"] as? [String: Any] {
                    return [.modelFailure(failure["kind"] as? String ?? reason?["kind"] as? String ?? "unknown")]
                }
            default: break
            }
            return []
        case "event":
            let event = value["event"]
            guard let record = LogEvent.parse(event) else { return [] }
            if let fact = RunFact(event, log: record) {
                return [.timeline([fact], replace: false), .event(record)]
            }
            return [.event(record)]
        default:
            return []
        }
    }
}
