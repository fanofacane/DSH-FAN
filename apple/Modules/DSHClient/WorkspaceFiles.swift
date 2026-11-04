// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
extension DSHClient {
    /// Bounded byte windows, checked against the Host's version and offsets.
    public func fileBytes(sessionId: String, path: String, maximum: Int = 50 * 1024 * 1024) async throws -> Data {
        let args: [String: Any] = ["workspaceFileScopeId": sessionId, "path": path]
        let stat = try await rpc("workspaceFiles/stat", args) as? [String: Any] ?? [:]
        let total = stat["bytes"] as? Int, version = stat["version"] as? String
        if let total, total > maximum { throw DSHError("E_PREVIEW_TOO_LARGE") }
        var data = Data()
        while true {
            try Task.checkCancellation()
            var request = args
            request["options"] = ["range": ["offset": data.count, "length": 1024 * 1024]]
            let row = try await rpc("workspaceFiles/readBytes", request) as? [String: Any] ?? [:]
            if let version, let actual = row["version"] as? String, actual != version { throw DSHError("E_FILE_CHANGED") }
            if let offset = row["offset"] as? Int, offset != data.count { throw DSHError("E_FILE_OFFSET") }
            let chunk: Data
            do { chunk = try BinaryRPC.bytes(row["data"]) } catch { throw DSHError("E_FILE_BYTES") }
            guard data.count + chunk.count <= maximum else { throw DSHError("E_PREVIEW_TOO_LARGE") }
            data.append(chunk)
            if row["eof"] as? Bool == true {
                if let total, data.count != total { throw DSHError("E_FILE_CHANGED") }
                return data
            }
            guard !chunk.isEmpty else { throw DSHError("E_FILE_READ_EMPTY") }
        }
    }
    public func officePDF(sessionId: String, path: String) async throws -> Data {
        let result = try await rpc("officeToPdf/render", ["workspaceFileScopeId": sessionId, "path": path, "priority": "foreground"]) as? [String: Any] ?? [:]
        do { return try BinaryRPC.bytes(result["data"]) } catch { throw DSHError("E_OFFICE_PREVIEW") }
    }
}
