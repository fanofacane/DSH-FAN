// SPDX-License-Identifier: AGPL-3.0-or-later
// Private-key import for SSH login: unencrypted OpenSSH keys (ed25519, ECDSA
// P-256/384/521) and PEM / PKCS#8 EC keys. NIO SSH has no RSA support, and
// passphrase-protected keys are not decrypted here.
import CryptoKit
import Foundation
import NIOSSH

public enum OpenSSHKey {
    public enum Problem: Error, Equatable { case unreadable, encrypted, unsupported(String) }

    public static func parse(_ text: String) throws -> NIOSSHPrivateKey {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("BEGIN OPENSSH PRIVATE KEY") { return try parseOpenSSH(trimmed) }
        if trimmed.contains("BEGIN RSA PRIVATE KEY") { throw Problem.unsupported("ssh-rsa") }
        if let key = try? P256.Signing.PrivateKey(pemRepresentation: trimmed) { return NIOSSHPrivateKey(p256Key: key) }
        if let key = try? P384.Signing.PrivateKey(pemRepresentation: trimmed) { return NIOSSHPrivateKey(p384Key: key) }
        if let key = try? P521.Signing.PrivateKey(pemRepresentation: trimmed) { return NIOSSHPrivateKey(p521Key: key) }
        if trimmed.contains("ENCRYPTED") { throw Problem.encrypted }
        throw Problem.unreadable
    }

    /// Why a key cannot be used, for the host form (nil when it parses).
    public static func problem(_ text: String) -> Problem? {
        do { _ = try parse(text); return nil } catch let problem as Problem { return problem } catch { return .unreadable }
    }

    private static func parseOpenSSH(_ text: String) throws -> NIOSSHPrivateKey {
        let body = text.components(separatedBy: .newlines).filter { !$0.hasPrefix("-----") }.joined()
        guard let data = Data(base64Encoded: body) else { throw Problem.unreadable }
        var reader = Reader(Array(data))
        let magic = Array("openssh-key-v1\0".utf8)
        guard try reader.bytes(magic.count) == magic else { throw Problem.unreadable }
        let cipher = try reader.string()
        _ = try reader.string() // kdf name
        _ = try reader.blob() // kdf options
        guard cipher == "none" else { throw Problem.encrypted }
        guard try reader.uint32() == 1 else { throw Problem.unreadable }
        _ = try reader.blob() // public key
        var priv = Reader(try reader.blob())
        guard try priv.uint32() == priv.uint32() else { throw Problem.unreadable }
        let type = try priv.string()
        switch type {
        case "ssh-ed25519":
            _ = try priv.blob()
            let secret = try priv.blob()
            guard secret.count == 64 else { throw Problem.unreadable }
            return NIOSSHPrivateKey(ed25519Key: try Curve25519.Signing.PrivateKey(rawRepresentation: secret[0..<32]))
        case "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521":
            _ = try priv.string() // curve
            _ = try priv.blob() // public point
            var scalar = try priv.blob()
            while scalar.first == 0, scalar.count > 1 { scalar.removeFirst() } // mpint sign byte
            func padded(_ size: Int) -> Data { Data(repeating: 0, count: max(0, size - scalar.count)) + Data(scalar) }
            switch type {
            case "ecdsa-sha2-nistp256": return NIOSSHPrivateKey(p256Key: try P256.Signing.PrivateKey(rawRepresentation: padded(32)))
            case "ecdsa-sha2-nistp384": return NIOSSHPrivateKey(p384Key: try P384.Signing.PrivateKey(rawRepresentation: padded(48)))
            default: return NIOSSHPrivateKey(p521Key: try P521.Signing.PrivateKey(rawRepresentation: padded(66)))
            }
        default:
            throw Problem.unsupported(type)
        }
    }

    private struct Reader {
        let data: [UInt8]
        var offset = 0
        init(_ data: [UInt8]) { self.data = data }

        mutating func bytes(_ count: Int) throws -> [UInt8] {
            guard count >= 0, offset + count <= data.count else { throw Problem.unreadable }
            defer { offset += count }
            return Array(data[offset..<(offset + count)])
        }
        mutating func uint32() throws -> UInt32 {
            try bytes(4).reduce(0) { $0 << 8 | UInt32($1) }
        }
        mutating func blob() throws -> [UInt8] { try bytes(Int(uint32())) }
        mutating func string() throws -> String { String(decoding: try blob(), as: UTF8.self) }
    }
}
