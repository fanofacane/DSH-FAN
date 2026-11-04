// SPDX-License-Identifier: AGPL-3.0-or-later
// Byte helpers for the ds-harness-remote protocol (port of
// 原 Flutter 版 dsh_remote/lib/src/util/bytes.dart; upstream: ds-harness-remote, MIT).
import CryptoKit
import Foundation

enum RemoteBytes {
    static func base64URL(_ data: some DataProtocol) -> String {
        Data(data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func fromBase64URL(_ text: String) -> Data? {
        let pad = (4 - text.count % 4) % 4
        if pad == 3 { return nil }
        let normal = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: normal + String(repeating: "=", count: pad))
    }

    /// Unpadded base64url whose unused trailing bits are zero.
    static func isCanonicalBase64URL(_ text: String) -> Bool {
        guard !text.isEmpty, text.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else { return false }
        let remainder = text.count % 4
        if remainder == 1 { return false }
        if remainder == 0 { return true }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard let last = alphabet.firstIndex(of: text.last!) else { return false }
        return remainder == 2 ? last & 15 == 0 : last & 3 == 0
    }

    static let identityKeyPattern = #"^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$"#
    static func isIdentityKey(_ text: String) -> Bool { text.range(of: identityKeyPattern, options: .regularExpression) != nil }

    static func random(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    static func uuidV7(_ date: Date = Date()) -> String {
        let ms = UInt64(date.timeIntervalSince1970 * 1000)
        var bytes = [UInt8](random(16))
        for i in 0..<6 { bytes[i] = UInt8((ms >> (8 * UInt64(5 - i))) & 0xff) }
        bytes[6] = (bytes[6] & 0x0f) | 0x70
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let h = Array(hex)
        return [String(h[0..<8]), String(h[8..<12]), String(h[12..<16]), String(h[16..<20]), String(h[20...])].joined(separator: "-")
    }

    /// First 48 bits of SHA-256 of the key, upper-case hex.
    static func identityFingerprint(_ publicKey: String) -> String {
        let digest = SHA256.hash(data: fromBase64URL(publicKey) ?? Data())
        return digest.prefix(6).map { String(format: "%02X", $0) }.joined()
    }

    /// `ABCD EF01 2345`.
    static func formatFingerprint(_ fingerprint: String) -> String {
        stride(from: 0, to: fingerprint.count, by: 4).map { start -> String in
            let a = fingerprint.index(fingerprint.startIndex, offsetBy: start)
            let b = fingerprint.index(a, offsetBy: min(4, fingerprint.count - start))
            return String(fingerprint[a..<b])
        }.joined(separator: " ")
    }

    static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }

    static func now() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

    /// JSON object from wire text; rejects duplicate keys like the Dart port.
    static func decodeWireJSON(_ text: String) -> Any? {
        guard !hasDuplicateKeys(text), let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func hasDuplicateKeys(_ text: String) -> Bool {
        let chars = Array(text.utf16)
        var objects: [Set<String>?] = []
        var i = 0
        func isSpace(_ c: UInt16) -> Bool { c == 0x20 || c == 0x0a || c == 0x0d || c == 0x09 }
        while i < chars.count {
            let c = chars[i]
            if c == 0x7b { objects.append([]) }
            else if c == 0x5b { objects.append(nil) }
            else if c == 0x7d || c == 0x5d { if !objects.isEmpty { objects.removeLast() } }
            else if c == 0x22 {
                let start = i
                i += 1
                while i < chars.count {
                    if chars[i] == 0x5c { i += 2; continue }
                    if chars[i] == 0x22 { break }
                    i += 1
                }
                var next = i + 1
                while next < chars.count, isSpace(chars[next]) { next += 1 }
                if next < chars.count, chars[next] == 0x3a, let last = objects.last, var keys = last {
                    let raw = String(utf16CodeUnits: Array(chars[start...min(i, chars.count - 1)]), count: min(i, chars.count - 1) - start + 1)
                    let key = (try? JSONSerialization.jsonObject(with: Data(raw.utf8), options: .fragmentsAllowed) as? String) ?? raw
                    if !keys.insert(key).inserted { return true }
                    objects[objects.count - 1] = keys
                }
            }
            i += 1
        }
        return false
    }

    static func encodeJSON(_ object: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

/// Protocol violation: the connection is closed.
struct RemoteProtocolError: Error, CustomStringConvertible {
    let code: String
    let message: String
    init(_ message: String, _ code: String = "INVALID_MESSAGE") { self.message = message; self.code = code }
    var description: String { "\(code): \(message)" }
}
