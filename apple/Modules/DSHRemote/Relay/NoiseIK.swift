// SPDX-License-Identifier: AGPL-3.0-or-later
// Noise_IK_25519_ChaChaPoly_SHA256 (port of 原 Flutter 版 dsh_remote/lib/src/crypto/
// noise_ik.dart; checked against ds-harness-remote fixtures/crypto/v1/noise-ik.json).
import CryptoKit
import Foundation

struct NoiseError: Error, CustomStringConvertible {
    let code: String
    let message: String
    init(_ code: String, _ message: String) { self.code = code; self.message = message }
    var description: String { "\(code): \(message)" }
}

enum X25519 {
    static func publicKey(_ privateKey: Data) throws -> Data {
        try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey).publicKey.rawRepresentation
    }

    static func dh(_ privateKey: Data, _ publicKey: Data) throws -> Data {
        let secret: SharedSecret
        do {
            secret = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
                .sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey))
        } catch {
            throw NoiseError("INVALID_KEY", "X25519 failed.")
        }
        let bytes = secret.withUnsafeBytes { Data($0) }
        if bytes.allSatisfy({ $0 == 0 }) { throw NoiseError("INVALID_KEY", "X25519 produced a low-order shared secret.") }
        return bytes
    }

    static func generate() -> (privateKey: Data, publicKey: Data) {
        let key = Curve25519.KeyAgreement.PrivateKey()
        return (key.rawRepresentation, key.publicKey.rawRepresentation)
    }
}

private func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
private func hmac(_ key: Data, _ data: Data) -> Data {
    Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
}
private func hkdf2(_ chainingKey: Data, _ input: Data) -> (Data, Data) {
    let temp = hmac(chainingKey, input)
    let one = hmac(temp, Data([0x01]))
    let two = hmac(temp, one + Data([0x02]))
    return (one, two)
}

final class NoiseCipher {
    private var key: Data?
    private(set) var nonce: UInt64 = 0
    init(_ key: Data? = nil) { self.key = key }
    var hasKey: Bool { key != nil }
    func initialize(_ key: Data) { self.key = key; nonce = 0 }

    private func nonceBytes() -> ChaChaPoly.Nonce {
        var bytes = Data(count: 12)
        for i in 0..<8 { bytes[4 + i] = UInt8((nonce >> (8 * UInt64(i))) & 0xff) }
        return try! ChaChaPoly.Nonce(data: bytes)
    }

    func encrypt(ad: Data, _ plaintext: Data) throws -> Data {
        guard let key else { return plaintext }
        guard nonce < 0x3fffffffffffffff else { throw NoiseError("NOISE_NONCE_EXHAUSTED", "Nonce space exhausted.") }
        let box = try ChaChaPoly.seal(plaintext, using: SymmetricKey(data: key), nonce: nonceBytes(), authenticating: ad)
        nonce += 1
        return box.ciphertext + box.tag
    }

    func decrypt(ad: Data, _ ciphertext: Data) throws -> Data {
        guard let key else { return ciphertext }
        guard ciphertext.count >= 16 else { throw NoiseError("NOISE_MESSAGE_INVALID", "Ciphertext shorter than its tag.") }
        guard nonce < 0x3fffffffffffffff else { throw NoiseError("NOISE_NONCE_EXHAUSTED", "Nonce space exhausted.") }
        let split = ciphertext.count - 16
        do {
            let box = try ChaChaPoly.SealedBox(nonce: nonceBytes(), ciphertext: ciphertext.prefix(split), tag: ciphertext.suffix(16))
            let plain = try ChaChaPoly.open(box, using: SymmetricKey(data: key), authenticating: ad)
            nonce += 1
            return plain
        } catch {
            throw NoiseError("NOISE_DECRYPT_FAILED", "Noise message authentication failed.")
        }
    }

    func destroy() { key = nil }
}

final class NoiseIKSession {
    enum Role { case initiator, responder }
    static let maxMessage = 65535

    let role: Role
    private let expectedRemoteStatic: Data
    private let staticPrivate: Data
    private let staticPublic: Data
    private let ephemeralSeed: Data?
    private var ephemeralPrivate: Data?
    private var remoteEphemeral: Data?
    private var remoteStatic: Data?
    private var ck: Data
    private var h: Data
    private let cipher = NoiseCipher()
    private var index = 0
    private(set) var send: NoiseCipher?
    private(set) var receive: NoiseCipher?
    private(set) var destroyed = false

    init(role: Role, localPrivateKey: Data, remotePublicKey: Data, prologue: Data, ephemeralPrivateKey: Data? = nil) throws {
        guard localPrivateKey.count == 32, remotePublicKey.count == 32 else { throw NoiseError("INVALID_KEY", "Keys must be 32 bytes.") }
        self.role = role
        staticPrivate = localPrivateKey
        staticPublic = try X25519.publicKey(localPrivateKey)
        expectedRemoteStatic = remotePublicKey
        ephemeralSeed = ephemeralPrivateKey
        let name = Data("Noise_IK_25519_ChaChaPoly_SHA256".utf8)
        h = name.count <= 32 ? name + Data(count: 32 - name.count) : sha256(name)
        ck = h
        mixHash(prologue)
        mixHash(role == .initiator ? remotePublicKey : staticPublic)
    }

    var complete: Bool { send != nil }
    var sendingCounter: UInt64 { send?.nonce ?? 0 }
    var receivingCounter: UInt64 { receive?.nonce ?? 0 }

    private func mixHash(_ data: Data) { h = sha256(h + data) }
    private func mixKey(_ input: Data) { let (a, b) = hkdf2(ck, input); ck = a; cipher.initialize(b) }
    private func encryptAndHash(_ plain: Data) throws -> Data { let c = try cipher.encrypt(ad: h, plain); mixHash(c); return c }
    private func decryptAndHash(_ c: Data) throws -> Data { let p = try cipher.decrypt(ad: h, c); mixHash(c); return p }

    private var writeTurn: Bool { (index == 0) == (role == .initiator) }

    func writeHandshake(_ payload: Data = Data()) throws -> Data {
        guard !destroyed, !complete, writeTurn else { throw NoiseError("NOISE_HANDSHAKE_ORDER", "Out-of-order handshake write.") }
        do {
            let eph = ephemeralSeed ?? X25519.generate().privateKey
            let ephPublic = try X25519.publicKey(eph)
            ephemeralPrivate = eph
            var out = ephPublic
            mixHash(ephPublic)
            if role == .initiator {
                mixKey(try X25519.dh(eph, expectedRemoteStatic))
                out += try encryptAndHash(staticPublic)
                mixKey(try X25519.dh(staticPrivate, expectedRemoteStatic))
            } else {
                mixKey(try X25519.dh(eph, remoteEphemeral!))
                mixKey(try X25519.dh(eph, remoteStatic!))
            }
            out += try encryptAndHash(payload)
            index += 1
            try finishIfReady()
            return out
        } catch { destroy(); throw error }
    }

    func readHandshake(_ message: Data) throws -> Data {
        guard !destroyed, !complete, !writeTurn else { throw NoiseError("NOISE_HANDSHAKE_ORDER", "Out-of-order handshake read.") }
        do {
            let minimum = role == .responder ? 32 + 32 + 16 + 16 : 32 + 16
            guard message.count <= Self.maxMessage, message.count >= minimum else {
                throw NoiseError("NOISE_MESSAGE_INVALID", "Handshake message has an invalid length.")
            }
            let bytes = Data(message)
            let re = bytes.prefix(32)
            remoteEphemeral = re
            mixHash(re)
            var offset = 32
            if role == .responder {
                mixKey(try X25519.dh(staticPrivate, re))
                let rs = try decryptAndHash(bytes.subdata(in: offset..<(offset + 48)))
                offset += 48
                remoteStatic = rs
                try verify(rs)
                mixKey(try X25519.dh(staticPrivate, rs))
            } else {
                remoteStatic = expectedRemoteStatic
                mixKey(try X25519.dh(ephemeralPrivate!, re))
                mixKey(try X25519.dh(staticPrivate, re))
            }
            let payload = try decryptAndHash(bytes.subdata(in: offset..<bytes.count))
            index += 1
            try finishIfReady()
            return payload
        } catch { destroy(); throw error }
    }

    func encrypt(_ plaintext: Data) throws -> Data {
        guard !destroyed, let send else { throw NoiseError("NOISE_NOT_READY", "Handshake not complete.") }
        guard plaintext.count + 16 <= Self.maxMessage else { throw NoiseError("NOISE_MESSAGE_INVALID", "Plaintext too large.") }
        return try send.encrypt(ad: Data(), plaintext)
    }

    func decrypt(_ ciphertext: Data) throws -> Data {
        guard !destroyed, let receive else { throw NoiseError("NOISE_NOT_READY", "Handshake not complete.") }
        do {
            guard ciphertext.count <= Self.maxMessage else { throw NoiseError("NOISE_MESSAGE_INVALID", "Message too large.") }
            return try receive.decrypt(ad: Data(), ciphertext)
        } catch { destroy(); throw error }
    }

    private func finishIfReady() throws {
        guard index >= 2 else { return }
        try verify(remoteStatic)
        let (k1, k2) = hkdf2(ck, Data())
        if role == .initiator { send = NoiseCipher(k1); receive = NoiseCipher(k2) } else { send = NoiseCipher(k2); receive = NoiseCipher(k1) }
    }

    private func verify(_ actual: Data?) throws {
        guard let actual, RemoteBytes.constantTimeEquals(actual, expectedRemoteStatic) else {
            destroy()
            throw NoiseError("PEER_IDENTITY_MISMATCH", "The Noise peer static key does not match local trust.")
        }
    }

    func destroy() {
        guard !destroyed else { return }
        destroyed = true
        cipher.destroy(); send?.destroy(); receive?.destroy()
        send = nil; receive = nil
    }

    static func prologue(connectionId: String, hostDeviceId: String, clientDeviceId: String) -> Data {
        Data("DSH-REMOTE\0v=1\0connection=\(connectionId)\0host=\(hostDeviceId)\0client=\(clientDeviceId)".utf8)
    }
}
