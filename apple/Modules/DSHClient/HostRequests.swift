// SPDX-License-Identifier: AGPL-3.0-or-later
// `$events` waterfalls that wait for a person: tool approvals and the
// `ask_user_question` tool. Mirrors ApprovalRequest / UserQuestionRequest in
// 原 Flutter 版 dsh_client/lib/src/models.dart.
import Foundation

public struct ApprovalRequest: Identifiable, Sendable, Equatable {
    public let id: String          // eventId
    public let sessionId: String   // agentId
    public let toolName: String
    public let callId: String?
    /// Localized presentation text keyed by locale (`en` always present).
    public let displayReason: [String: String]
    public let reason: String?

    public func describe(locale: Locale = .current) -> String? {
        let language = locale.language.languageCode?.identifier ?? "en"
        let script = locale.language.script?.identifier
        let keys = [script.map { "\(language)-\($0)" }, language == "zh" ? "zh-CN" : nil, language, "en"].compactMap { $0 }
        for key in keys { if let text = displayReason[key] { return text } }
        return reason
    }
}

public struct QuestionOption: Sendable, Equatable, Hashable {
    public let label: String
    public let description: String?
}

public struct UserQuestion: Identifiable, Sendable, Equatable {
    public let id: String
    public let question: String
    public let detail: String?
    public let header: String?
    public let options: [QuestionOption]
    public let multiSelect: Bool
}

public struct QuestionRequest: Identifiable, Sendable, Equatable {
    public let id: String          // eventId
    public let sessionId: String
    public let questions: [UserQuestion]
}

public struct QuestionAnswer: Sendable {
    public let id: String
    public let selected: [String]
    public let custom: String?
    public init(id: String, selected: [String], custom: String? = nil) {
        self.id = id; self.selected = selected; self.custom = custom
    }
}

public enum HostRequest: Sendable, Equatable {
    case approval(ApprovalRequest)
    case question(QuestionRequest)
    /// Answered elsewhere or withdrawn (turn cancelled, agent released).
    case cancelled(eventId: String)
    /// `api-session/status` emit: a session started or stopped running.
    case sessionStatus(sessionId: String, running: Bool)

    static func parse(_ frame: [String: Any]) -> HostRequest? {
        switch frame["type"] as? String {
        case "waterfall":
            let eventId = frame["eventId"] as? String ?? ""
            let agentId = frame["agentId"] as? String ?? ""
            let request = frame["request"] as? [String: Any] ?? [:]
            switch frame["event"] as? String {
            case "approval/request":
                let display = (request["displayReason"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
                return .approval(ApprovalRequest(id: eventId, sessionId: agentId,
                                                 toolName: request["toolName"] as? String ?? "tool",
                                                 callId: request["callId"] as? String,
                                                 displayReason: display, reason: request["reason"] as? String))
            case "user-questions/request":
                let questions = (request["questions"] as? [[String: Any]] ?? []).map { q in
                    UserQuestion(id: q["id"] as? String ?? "", question: q["question"] as? String ?? "",
                                 detail: q["detail"] as? String, header: q["header"] as? String,
                                 options: (q["options"] as? [[String: Any]] ?? []).map {
                                     QuestionOption(label: $0["label"] as? String ?? "", description: $0["description"] as? String)
                                 },
                                 multiSelect: q["multiSelect"] as? Bool == true)
                }
                return .question(QuestionRequest(id: eventId, sessionId: agentId, questions: questions))
            default:
                return nil
            }
        case "cancel":
            return .cancelled(eventId: frame["eventId"] as? String ?? "")
        case "emit":
            guard frame["event"] as? String == "api-session/status", let args = frame["args"] as? [Any],
                  let id = args.first as? String else { return nil }
            return .sessionStatus(sessionId: id, running: args.count > 1 && (args[1] as? Bool) == true)
        default:
            return nil
        }
    }
}

public struct PermissionPreset: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let description: String?
}

extension DSHClient {
    /// `$events/result` on behalf of this client's current `$events` stream.
    func respondHostEvent(_ eventId: String, outcome: [String: Any]) async throws {
        for attempt in 0..<3 {
            let mux = try await muxConnection()
            guard let clientId = mux.clientId else { throw DSHError("E_MUX_NOT_READY") }
            do {
                try await rpc("$events/result", ["clientId": clientId, "eventId": eventId, "outcome": outcome])
                return
            } catch let error as DSHError where attempt < 2 && error.code == "E_RPC_REFUSED" {
                try await Task.sleep(nanoseconds: 300_000_000) // Stream generation changed; retry.
            }
        }
    }

    /// One-shot grant (`allowed-once`) or rejection (`rejected`). There is no "always allow".
    public func respondApproval(_ request: ApprovalRequest, allow: Bool) async throws {
        try await respondHostEvent(request.id, outcome: ["kind": "result", "value": allow ? "allowed-once" : "rejected"])
    }

    public func answerQuestion(_ request: QuestionRequest, answers: [QuestionAnswer]) async throws {
        let rows: [[String: Any]] = answers.map { answer in
            var row: [String: Any] = ["id": answer.id, "selected": answer.selected]
            if let custom = answer.custom { row["custom"] = custom }
            return row
        }
        try await respondHostEvent(request.id, outcome: ["kind": "result", "value": ["answers": rows]])
    }

    public func declineQuestion(_ request: QuestionRequest) async throws {
        try await respondHostEvent(request.id, outcome: ["kind": "rejected",
            "error": ["name": "UserQuestionError", "message": "declined"]])
    }

    /// `permissionPresets/catalog`: options and the default preset.
    public func permissionPresets() async throws -> (options: [PermissionPreset], defaultPreset: String) {
        let value = try await rpc("permissionPresets/catalog") as? [String: Any] ?? [:]
        let options = (value["options"] as? [[String: Any]] ?? []).compactMap { row -> PermissionPreset? in
            guard let id = row["value"] as? String, !id.isEmpty else { return nil }
            return PermissionPreset(id: id, name: row["name"] as? String ?? id, description: row["description"] as? String)
        }
        return (options, value["defaultPreset"] as? String ?? "")
    }

    /// Switches a session's permission preset (the `/permission` command).
    public func setPermissionPreset(sessionId: String, preset: String) async throws {
        guard preset.range(of: #"^[a-z][a-z0-9-]*$"#, options: .regularExpression) != nil else { throw DSHError("E_PRESET") }
        try await rpc("commands/execute", ["agentId": sessionId, "line": "/permission \(preset)",
                                           "submittedAttachments": [Any]()])
    }

    public func renameSession(_ sessionId: String, title: String) async throws {
        try await rpc("session/rename", ["request": ["sessionId": sessionId, "title": title]])
    }

    /// Permanent deletion through the dsh-fan bridge (`POST /dsh-fan/v1/sessions/delete`).
    /// Never retried: after a lost reply the outcome is unknown.
    public func deleteSession(_ sessionId: String) async throws {
        guard !sessionId.isEmpty, sessionId.count <= 256,
              sessionId.range(of: #"[\x00-\x1f\x7f]"#, options: .regularExpression) == nil else { throw DSHError("E_SESSION_ID") }
        // The dsh-fan bridge is only on the phone's engine, not on remote Hosts.
        if carrier != nil { throw DSHError("E_DELETE_UNSUPPORTED") }
        var request = URLRequest(url: baseURL.appendingPathComponent("dsh-fan/v1/sessions/delete"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authCookie, forHTTPHeaderField: "Cookie")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["sessionId": sessionId])
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200 else {
            if let code = (body?["error"] as? [String: Any])?["code"] as? String, !code.isEmpty, code.count <= 80 { throw DSHError(code) }
            throw DSHError([404, 405, 501].contains(status) ? "E_DELETE_UNSUPPORTED" : "E_DELETE_HTTP_\(status)")
        }
        guard body?["deleted"] as? Bool == true, body?["sessionId"] as? String == sessionId else { throw DSHError("E_DELETE_UNCONFIRMED") }
    }
}
