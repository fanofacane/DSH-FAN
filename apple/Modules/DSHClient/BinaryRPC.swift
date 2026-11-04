// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public enum BinaryRPCFailure: Error { case malformed }

/// Restores the byte attachments of the engine's multipart RPC envelope.
/// Parsing never decodes binary parts as text and rejects ambiguous fields.
public enum BinaryRPC {
    public static func decode(_ body: Data, contentType: String) throws -> [String: Any] {
        let parameters = contentType.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let parameter = parameters.first(where: { $0.lowercased().hasPrefix("boundary=") }) else { throw BinaryRPCFailure.malformed }
        var boundary = String(parameter.dropFirst(9))
        if boundary.hasPrefix("\""), boundary.hasSuffix("\"") { boundary = String(boundary.dropFirst().dropLast()) }
        guard !boundary.isEmpty, boundary.utf8.count <= 200, !boundary.contains("\r"), !boundary.contains("\n") else { throw BinaryRPCFailure.malformed }
        let delimiter = Data(("--" + boundary).utf8), separator = Data("\r\n\r\n".utf8)
        guard var at = body.range(of: delimiter)?.lowerBound else { throw BinaryRPCFailure.malformed }
        var parts: [String: Data] = [:]
        while true {
            let begin = at + delimiter.count
            guard begin + 2 <= body.count else { throw BinaryRPCFailure.malformed }
            if body[begin..<(begin + 2)] == Data("--".utf8) { break }
            guard body[begin..<(begin + 2)] == Data("\r\n".utf8),
                  let headers = body.range(of: separator, in: (begin + 2)..<body.count) else { throw BinaryRPCFailure.malformed }
            let header = String(decoding: body[(begin + 2)..<headers.lowerBound], as: UTF8.self)
            let expression = try NSRegularExpression(pattern: #"(?:^|;)\s*name="([^"]*)""#, options: [.caseInsensitive])
            let disposition = header.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-disposition:") } ?? ""
            guard let match = expression.firstMatch(in: disposition, range: NSRange(disposition.startIndex..., in: disposition)),
                  let nameRange = Range(match.range(at: 1), in: disposition),
                  let next = body.range(of: Data("\r\n".utf8) + delimiter, in: headers.upperBound..<body.count) else { throw BinaryRPCFailure.malformed }
            let name = String(disposition[nameRange])
            guard parts[name] == nil else { throw BinaryRPCFailure.malformed }
            parts[name] = Data(body[headers.upperBound..<next.lowerBound]); at = next.lowerBound + 2
        }
        guard let metadata = parts.removeValue(forKey: "metadata"),
              var envelope = try JSONSerialization.jsonObject(with: metadata) as? [String: Any],
              var result = envelope["result"] as? [String: Any], result["ok"] as? Bool == true,
              let attachments = envelope["attachments"] as? [[String: Any]], !attachments.isEmpty else { throw BinaryRPCFailure.malformed }
        var value: Any = result["value"] ?? NSNull()
        func replacing(_ object: Any, path: ArraySlice<Any>, bytes: Data) throws -> Any {
            guard let head = path.first else {
                guard object is NSNull else { throw BinaryRPCFailure.malformed }; return bytes
            }
            if var map = object as? [String: Any], let key = head as? String, let child = map[key] {
                map[key] = try replacing(child, path: path.dropFirst(), bytes: bytes); return map
            }
            if var list = object as? [Any], let index = head as? Int, list.indices.contains(index) {
                list[index] = try replacing(list[index], path: path.dropFirst(), bytes: bytes); return list
            }
            throw BinaryRPCFailure.malformed
        }
        for attachment in attachments {
            guard attachment["codec"] as? String == "bytes", let part = attachment["part"] as? String,
                  let path = attachment["path"] as? [Any], let bytes = parts.removeValue(forKey: part) else { throw BinaryRPCFailure.malformed }
            value = try replacing(value, path: path[...], bytes: bytes)
        }
        guard parts.isEmpty else { throw BinaryRPCFailure.malformed }
        result["value"] = value; envelope["result"] = result
        return envelope
    }
    public static func bytes(_ value: Any?) throws -> Data {
        if let data = value as? Data { return data }
        if let base64 = value as? String, let data = Data(base64Encoded: base64) { return data }
        if let numbers = value as? [Int], numbers.allSatisfy({ (0...255).contains($0) }) { return Data(numbers.map(UInt8.init)) }
        throw BinaryRPCFailure.malformed
    }
}
