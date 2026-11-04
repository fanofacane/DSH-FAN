// SPDX-License-Identifier: AGPL-3.0-or-later
// Control frames, DSHF fragments and Remote messages (port of
// 原 Flutter 版 dsh_remote/lib/src/protocol/{control,messages}.dart; upstream MIT).
import Foundation

enum RemoteWire {
    static let protocolVersion = 1
    static let maxControlFrameBytes = 64 * 1024
    static let maxRelayFrameBytes = 1024 * 1024

    static let controlTypes: Set<String> = [
        "hello", "hello.ack", "connect.request", "connect.incoming", "connect.accepted", "connect.rejected",
        "secure.handshake", "relay", "signal.offer", "signal.answer", "signal.ice", "transport.selected",
        "ping", "pong", "error",
    ]

    struct Frame {
        let id: String
        let type: String
        let timestamp: Int
        let payload: [String: Any]

        init(_ type: String, _ payload: [String: Any], id: String = RemoteBytes.uuidV7(), timestamp: Int = RemoteBytes.now()) {
            self.type = type; self.payload = payload; self.id = id; self.timestamp = timestamp
        }

        var json: [String: Any] { ["v": protocolVersion, "id": id, "type": type, "timestamp": timestamp, "payload": payload] }
    }

    struct Limits { var control = maxControlFrameBytes; var relay = maxRelayFrameBytes }

    static func encode(_ frame: Frame, limits: Limits) throws -> String {
        let text = RemoteBytes.encodeJSON(frame.json)
        let limit = frame.type == "relay" ? min(limits.relay, maxRelayFrameBytes) : min(limits.control, maxControlFrameBytes)
        if text.utf8.count > limit { throw RemoteProtocolError("Control frame exceeds its limit.", "FRAME_TOO_LARGE") }
        return text
    }

    /// Control socket frame: strict envelope, known type, payload checks.
    static func decodeControl(_ text: String, limits: Limits) throws -> Frame {
        let bytes = text.utf8.count
        guard bytes <= maxRelayFrameBytes else { throw RemoteProtocolError("Control frame too large.", "FRAME_TOO_LARGE") }
        guard let map = RemoteBytes.decodeWireJSON(text) as? [String: Any] else { throw RemoteProtocolError("Control frame is not JSON.") }
        guard Set(map.keys).isSubset(of: ["v", "id", "type", "timestamp", "payload"]) else {
            throw RemoteProtocolError("Unexpected Control envelope field.")
        }
        guard (map["v"] as? Int) == protocolVersion else { throw RemoteProtocolError("Unsupported version.", "UNSUPPORTED_VERSION") }
        guard let id = map["id"] as? String, !id.isEmpty, let type = map["type"] as? String, controlTypes.contains(type),
              let timestamp = map["timestamp"] as? Int, timestamp > 0, let payload = map["payload"] as? [String: Any] else {
            throw RemoteProtocolError("Invalid Control frame.")
        }
        let limit = type == "relay" ? min(limits.relay, maxRelayFrameBytes) : min(limits.control, maxControlFrameBytes)
        if bytes > limit { throw RemoteProtocolError("Control frame exceeds its limit.", "FRAME_TOO_LARGE") }
        try validate(type, payload)
        return Frame(type, payload, id: id, timestamp: timestamp)
    }

    /// Relay node data socket frame: any type, fixed envelope.
    static func decodeData(_ text: String, limits: Limits) throws -> Frame {
        guard text.utf8.count <= min(limits.relay, maxRelayFrameBytes),
              let map = RemoteBytes.decodeWireJSON(text) as? [String: Any], map.count == 5,
              (map["v"] as? Int) == protocolVersion, let id = map["id"] as? String, !id.isEmpty,
              let type = map["type"] as? String, !type.isEmpty, let timestamp = map["timestamp"] as? Int, timestamp > 0,
              let payload = map["payload"] as? [String: Any] else { throw RemoteProtocolError("Invalid Relay data frame.") }
        return Frame(type, payload, id: id, timestamp: timestamp)
    }

    static func validate(_ type: String, _ p: [String: Any]) throws {
        func nonEmpty(_ key: String) throws {
            guard let v = p[key] as? String, !v.isEmpty else { throw RemoteProtocolError("\(key) must be a non-empty string.") }
        }
        func positive(_ key: String, max: Int? = nil) throws {
            guard let v = p[key] as? Int, v > 0, max.map({ v <= $0 }) ?? true else { throw RemoteProtocolError("\(key) is invalid.") }
        }
        func base64(_ key: String) throws {
            guard let v = p[key] as? String, RemoteBytes.isCanonicalBase64URL(v) else { throw RemoteProtocolError("\(key) must be base64url.") }
        }
        switch type {
        case "hello.ack":
            guard (p["protocol"] as? Int) == protocolVersion else { throw RemoteProtocolError("Unsupported protocol.", "UNSUPPORTED_VERSION") }
            try nonEmpty("serverVersion"); try nonEmpty("connectionSessionId")
            try positive("heartbeatIntervalMs")
            try positive("maxControlFrameBytes", max: maxControlFrameBytes)
            try positive("maxRelayFrameBytes", max: maxRelayFrameBytes)
        case "connect.accepted", "connect.rejected":
            try nonEmpty("connectionId")
        case "secure.handshake":
            try nonEmpty("connectionId"); try nonEmpty("targetDeviceId")
            guard let step = p["step"] as? Int, step == 1 || step == 2 else { throw RemoteProtocolError("Invalid step.") }
            try base64("data")
        case "relay":
            try nonEmpty("connectionId"); try nonEmpty("targetDeviceId")
            guard let counter = p["counter"] as? Int, counter >= 0 else { throw RemoteProtocolError("Invalid counter.") }
            try base64("ciphertext")
        case "ping", "pong":
            try nonEmpty("nonce")
        case "error":
            try nonEmpty("code"); try nonEmpty("message")
        default:
            break
        }
    }
}

/// DSHF fragmentation of secure messages above 48 KiB (reassembly ≤ 4 MiB).
final class SecureMessageCodec {
    static let chunk = 48 * 1024
    static let maxMessage = 4 * 1024 * 1024
    private static let magic: [UInt8] = [0x44, 0x53, 0x48, 0x46]
    private static let header = 17
    private var nextId: UInt32 = 1
    private var assemblies: [UInt32: (total: Int, totalBytes: Int, data: Data)] = [:]

    func encode(_ message: Data) throws -> [Data] {
        guard message.count <= Self.maxMessage else { throw RemoteProtocolError("Secure message exceeds the reassembly limit.", "FRAME_TOO_LARGE") }
        guard message.count > Self.chunk else { return [message] }
        let id = nextId
        nextId = id == UInt32.max ? 1 : id + 1
        let total = (message.count + Self.chunk - 1) / Self.chunk
        let bytes = Data(message)
        return (0..<total).map { index in
            let start = index * Self.chunk
            let end = min(start + Self.chunk, bytes.count)
            var frame = Data(Self.magic)
            frame.append(1)
            frame.append(contentsOf: withUnsafeBytes(of: id.bigEndian, Array.init))
            frame.append(contentsOf: withUnsafeBytes(of: UInt16(index).bigEndian, Array.init))
            frame.append(contentsOf: withUnsafeBytes(of: UInt16(total).bigEndian, Array.init))
            frame.append(contentsOf: withUnsafeBytes(of: UInt32(bytes.count).bigEndian, Array.init))
            frame.append(bytes.subdata(in: start..<end))
            return frame
        }
    }

    /// The whole message, or nil while fragments are still arriving.
    func decode(_ frame: Data) throws -> Data? {
        let f = [UInt8](frame)
        guard f.count >= 4, Array(f[0..<4]) == Self.magic else { return frame }
        guard f.count >= Self.header, f[4] == 1 else { throw RemoteProtocolError("Secure fragment header is invalid.") }
        func u32(_ o: Int) -> Int { Int(f[o]) << 24 | Int(f[o + 1]) << 16 | Int(f[o + 2]) << 8 | Int(f[o + 3]) }
        func u16(_ o: Int) -> Int { Int(f[o]) << 8 | Int(f[o + 1]) }
        let id = UInt32(u32(5)), index = u16(9), total = u16(11), totalBytes = u32(13)
        guard id != 0, total >= 2, index < total, totalBytes > Self.chunk, totalBytes <= Self.maxMessage,
              total == (totalBytes + Self.chunk - 1) / Self.chunk else { throw RemoteProtocolError("Secure fragment metadata is invalid.") }
        let remaining = totalBytes - index * Self.chunk
        let length = f.count - Self.header
        guard length == min(remaining, Self.chunk) else { throw RemoteProtocolError("Secure fragment length is invalid.") }
        var assembly = assemblies[id]
        if assembly == nil {
            guard index == 0, assemblies.count < 8 else { throw RemoteProtocolError("Secure fragment sequence is invalid.") }
            assembly = (total, totalBytes, Data())
        }
        let soFar = (assembly!.data.count + Self.chunk - 1) / Self.chunk
        guard assembly!.total == total, assembly!.totalBytes == totalBytes, index == soFar else {
            assemblies[id] = nil
            throw RemoteProtocolError("Secure fragment sequence is invalid.")
        }
        assembly!.data.append(contentsOf: f[Self.header...])
        if index + 1 < total { assemblies[id] = assembly; return nil }
        assemblies[id] = nil
        guard assembly!.data.count == totalBytes else { throw RemoteProtocolError("Secure message length is invalid.") }
        return assembly!.data
    }

    func reset() { nextId = 1; assemblies = [:] }
}

/// `{v, id, type, timestamp, payload}` inside the secure channel.
struct RemoteMessage {
    static let types: Set<String> = ["rpc.request", "rpc.response", "rpc.error", "event"]
    let id: String
    let type: String
    let payload: Any?

    static func request(_ method: String, _ params: Any) -> (id: String, data: Data) {
        let id = RemoteBytes.uuidV7()
        let json: [String: Any] = ["v": RemoteWire.protocolVersion, "id": id, "type": "rpc.request",
                                   "timestamp": RemoteBytes.now(), "payload": ["method": method, "params": params]]
        return (id, Data(RemoteBytes.encodeJSON(json).utf8))
    }

    static func decode(_ data: Data) throws -> RemoteMessage {
        guard let text = String(data: data, encoding: .utf8), let map = RemoteBytes.decodeWireJSON(text) as? [String: Any] else {
            throw RemoteProtocolError("Remote message is not valid UTF-8 JSON.")
        }
        guard (map["v"] as? Int) == RemoteWire.protocolVersion else { throw RemoteProtocolError("Unsupported version.", "UNSUPPORTED_VERSION") }
        guard let id = map["id"] as? String, !id.isEmpty, let type = map["type"] as? String, types.contains(type),
              let timestamp = map["timestamp"] as? Int, timestamp > 0 else { throw RemoteProtocolError("Invalid Remote message.") }
        return RemoteMessage(id: id, type: type, payload: map["payload"])
    }
}
