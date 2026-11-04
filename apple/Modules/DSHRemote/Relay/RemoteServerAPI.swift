// SPDX-License-Identifier: AGPL-3.0-or-later
// REST API of a ds-harness-remote Server (port of
// 原 Flutter 版 dsh_remote/lib/src/server/server_api.dart; upstream MIT).
import Foundation

struct RemoteAPIError: Error, CustomStringConvertible {
    let code: String
    let message: String
    var status: Int?
    var retryable = false
    var isAuthFailure: Bool { ["AUTH_INVALID", "TOKEN_EXPIRED", "AUTH_REQUIRED", "ACCOUNT_AUTH_REQUIRED"].contains(code) }
    var description: String { "\(code)\(status.map { " (HTTP \($0))" } ?? ""): \(message)" }
    var failure: RemoteFailure {
        RemoteFailure(code, message, retryable: retryable || code == "CONNECTION_FAILED" || code == "HOST_OFFLINE")
    }
}

/// Validates a Server address: a bare origin, HTTPS (HTTP only for private hosts).
public enum RemoteServerURL {
    public static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }
        if text.range(of: #"^[a-zA-Z][a-zA-Z\d+.-]*://"#, options: .regularExpression) == nil { text = "https://" + text }
        guard let parts = URLComponents(string: text), let host = parts.host, !host.isEmpty, parts.user == nil,
              parts.query == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/" else { return nil }
        let scheme = parts.scheme?.lowercased() ?? ""
        guard scheme == "https" || (scheme == "http" && isPrivate(host)) else { return nil }
        var out = URLComponents()
        out.scheme = scheme; out.host = host; out.port = parts.port
        return out.url
    }

    static func isPrivate(_ host: String) -> Bool {
        if ["localhost", "127.0.0.1", "::1"].contains(host) { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return host.hasSuffix(".local") || host.hasSuffix(".test") || host.hasSuffix(".localhost") }
        let (a, b) = (parts[0], parts[1])
        return a == 10 || a == 127 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168)
            || (a == 169 && b == 254) || (a == 100 && (64...127).contains(b))
    }
}

struct RemoteTokens {
    let accessToken: String
    let accessExpires: Date
    let refreshToken: String
    let refreshExpires: Date

    init(_ value: Any?) throws {
        guard let map = value as? [String: Any],
              Set(map.keys).isSubset(of: ["accessToken", "accessTokenExpiresAt", "refreshToken", "refreshTokenExpiresAt"]),
              let access = map["accessToken"] as? String, (16...8192).contains(access.utf8.count),
              let refresh = map["refreshToken"] as? String, (16...8192).contains(refresh.utf8.count),
              let accessAt = map["accessTokenExpiresAt"] as? Int, accessAt > 0,
              let refreshAt = map["refreshTokenExpiresAt"] as? Int, refreshAt > 0 else {
            throw RemoteAPIError(code: "INVALID_MESSAGE", message: "The server returned invalid device credentials.")
        }
        accessToken = access; refreshToken = refresh
        accessExpires = Date(timeIntervalSince1970: Double(accessAt) / 1000)
        refreshExpires = Date(timeIntervalSince1970: Double(refreshAt) / 1000)
    }
}

public struct RemoteLoginProvider: Sendable, Identifiable, Equatable {
    public let id: String
    public let displayName: String
    let qrStartPath: String?
}

struct RemoteHostListing {
    let deviceId: String
    let name: String
    let platform: String
    let online: Bool
    let clientVersion: String?
    let harnessVersion: String?
    let lastSeen: Date?
}

struct RemotePeer {
    let deviceId: String
    let name: String
    let role: String
    let platform: String
    let identityKey: String
    let online: Bool?
    let clientVersion: String?
    let harnessVersion: String?
}

final class RemoteServerAPI: @unchecked Sendable {
    let server: URL
    private let session: URLSession

    init(server: URL) {
        self.server = server
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    var controlSocketURL: URL {
        var parts = URLComponents(url: server, resolvingAgainstBaseURL: false)!
        parts.scheme = server.scheme == "https" ? "wss" : "ws"
        parts.path = "/ws/v1/connect"
        return parts.url!
    }

    func oauthProviders() async throws -> [RemoteLoginProvider] {
        let body: Any?
        do { body = try await request("GET", "/api/v1/auth/oauth/providers") } catch let error as RemoteAPIError where error.status == 404 {
            return [] // Self-hosted Server: email and password only.
        }
        guard let items = (body as? [String: Any])?["items"] as? [[String: Any]] else {
            throw RemoteAPIError(code: "INVALID_MESSAGE", message: "The server returned invalid OAuth providers.")
        }
        return items.compactMap { item in
            guard let id = item["id"] as? String, let name = item["displayName"] as? String else { return nil }
            let qr = item["qrStartUrl"] as? String
            return RemoteLoginProvider(id: id, displayName: name, qrStartPath: qr.flatMap { Self.isAuthPath($0) ? $0 : nil })
        }
    }

    func startQRLogin(_ provider: RemoteLoginProvider) async throws -> (qrId: String, scanURL: URL, expiresIn: TimeInterval) {
        guard let path = provider.qrStartPath else { throw RemoteAPIError(code: "INVALID_MESSAGE", message: "No QR sign-in for this provider.") }
        let body = try await request("POST", path, body: [String: Any]()) as? [String: Any]
        guard let qrId = body?["qrId"] as? String, qrId.count >= 20, let expires = body?["expiresIn"] as? Int, expires > 0,
              let scan = (body?["scanUrl"] as? String).flatMap(URL.init(string:)),
              scan.scheme == server.scheme, scan.host == server.host, scan.port == server.port else {
            throw RemoteAPIError(code: "INVALID_MESSAGE", message: "The server returned an invalid QR sign-in session.")
        }
        return (qrId, scan, TimeInterval(expires))
    }

    enum QRStatus { case pending, expired, complete(String) }

    func pollQRLogin(_ qrId: String) async throws -> QRStatus {
        let encoded = qrId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? qrId
        let body = try await request("GET", "/api/v1/auth/oauth/qr/\(encoded)") as? [String: Any]
        switch body?["status"] as? String {
        case "pending": return .pending
        case "expired": return .expired
        case "complete":
            if let token = body?["token"] as? String, token.count >= 16 { return .complete(token) }
        default: break
        }
        throw RemoteAPIError(code: "INVALID_MESSAGE", message: "The server returned an invalid QR sign-in status.")
    }

    func login(email: String, password: String) async throws -> (token: String, account: String) {
        let body = try await request("POST", "/api/v1/auth/login",
                                     body: ["email": email.trimmingCharacters(in: .whitespaces), "password": password]) as? [String: Any]
        guard let token = body?["token"] as? String, token.count >= 16, let account = body?["account"] as? String, !account.isEmpty else {
            throw RemoteAPIError(code: "INVALID_MESSAGE", message: "The server returned an invalid account login.")
        }
        return (token, account)
    }

    func accountMe(_ accountToken: String) async throws -> String {
        guard let account = (try await request("GET", "/api/v1/auth/me", bearer: accountToken) as? [String: Any])?["account"] as? String,
              !account.isEmpty else { throw RemoteAPIError(code: "INVALID_MESSAGE", message: "Invalid account profile.") }
        return account
    }

    func registerDevice(_ device: [String: Any], accountToken: String) async throws -> RemoteTokens {
        try RemoteTokens(try await request("POST", "/api/v1/devices/register", body: ["v": 1, "device": device], bearer: accountToken))
    }

    func refresh(deviceId: String, refreshToken: String) async throws -> RemoteTokens {
        try RemoteTokens(try await request("POST", "/api/v1/auth/refresh", body: ["deviceId": deviceId, "refreshToken": refreshToken]))
    }

    func listHosts(_ accessToken: String) async throws -> [RemoteHostListing] {
        guard let items = (try await request("GET", "/api/v1/devices", bearer: accessToken) as? [String: Any])?["items"] as? [[String: Any]] else {
            throw RemoteAPIError(code: "INVALID_MESSAGE", message: "The server returned an invalid device list.")
        }
        return items.compactMap { item in
            guard item["role"] as? String == "host", let id = item["deviceId"] as? String, let name = item["name"] as? String,
                  let platform = item["platform"] as? String, !((item["membershipId"] as? String) ?? "").isEmpty else { return nil }
            let seen = (item["lastSeenAt"] as? Int).flatMap { $0 > 0 ? Date(timeIntervalSince1970: Double($0) / 1000) : nil }
            return RemoteHostListing(deviceId: id, name: name, platform: platform, online: item["online"] as? Bool == true,
                                     clientVersion: item["clientVersion"] as? String, harnessVersion: item["harnessVersion"] as? String,
                                     lastSeen: seen)
        }
    }

    func device(_ accessToken: String, _ deviceId: String) async throws -> RemotePeer {
        let path = "/api/v1/devices/" + (deviceId.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) ?? deviceId)
        guard let item = try await request("GET", path, bearer: accessToken) as? [String: Any],
              let role = item["role"] as? String, role == "host" || role == "client",
              let id = item["deviceId"] as? String, !id.isEmpty, let name = item["name"] as? String, !name.isEmpty,
              let platform = item["platform"] as? String, let key = item["identityKey"] as? String, !key.isEmpty,
              !((item["membershipId"] as? String) ?? "").isEmpty else {
            throw RemoteAPIError(code: "INVALID_MESSAGE", message: "The server returned an invalid peer descriptor.")
        }
        var online = item["online"] as? Bool
        if online == nil, let presence = try? await request("GET", path + "/presence", bearer: accessToken) as? [String: Any] {
            online = presence["online"] as? Bool
        }
        return RemotePeer(deviceId: id, name: name, role: role, platform: platform, identityKey: key, online: online,
                          clientVersion: item["clientVersion"] as? String, harnessVersion: item["harnessVersion"] as? String)
    }

    func revokeSelf(_ accessToken: String) async throws { _ = try await request("DELETE", "/api/v1/devices/self", bearer: accessToken) }

    // MARK: HTTP

    private static func isAuthPath(_ value: String) -> Bool {
        guard value.hasPrefix("/api/v1/auth/"),
              value.range(of: ##"[\x00-\x1f\x7f\s\\#]"##, options: .regularExpression) == nil else { return false }
        return !(value.split(separator: "?").first ?? "").split(separator: "/").contains { $0 == "." || $0 == ".." || $0.contains("%") }
    }

    private func request(_ method: String, _ path: String, body: Any? = nil, bearer: String? = nil) async throws -> Any? {
        guard let url = URL(string: path, relativeTo: server)?.absoluteURL,
              url.scheme == server.scheme, url.host == server.host, url.port == server.port else {
            throw RemoteAPIError(code: "INVALID_MESSAGE", message: "Refusing a cross-origin Server request.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer { request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch {
            throw RemoteAPIError(code: "CONNECTION_FAILED", message: "Server request failed: \(error.localizedDescription)", retryable: true)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let decoded = data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        if (200..<300).contains(status) {
            if !data.isEmpty && decoded == nil { throw RemoteAPIError(code: "INVALID_MESSAGE", message: "The server returned invalid JSON.", status: status) }
            return decoded
        }
        let map = decoded as? [String: Any]
        let error = map?["error"] as? [String: Any]
        let code = error?["code"] as? String ?? map?["code"] as? String ?? Self.statusCode(status)
        let message = error?["message"] as? String ?? map?["detail"] as? String ?? "The server rejected the request."
        throw RemoteAPIError(code: code, message: message, status: status,
                             retryable: error?["retryable"] as? Bool == true || status >= 500 || status == 429)
    }

    private static func statusCode(_ status: Int) -> String {
        switch status {
        case 401: "AUTH_INVALID"
        case 403: "AUTH_REQUIRED"
        case 404: "DEVICE_NOT_FOUND"
        case 409: "DEVICE_OWNERSHIP_REQUIRED"
        case 429: "RATE_LIMITED"
        default: status >= 500 ? "CONNECTION_FAILED" : "INVALID_MESSAGE"
        }
    }
}
