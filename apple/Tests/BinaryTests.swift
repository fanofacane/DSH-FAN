// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing
@testable import DSHClient
struct BinaryTests {
    @Test func contracts() throws {
        let bytes = Data([0, 255, 13, 10, 3, 128])
        let metadata: [String: Any] = ["type": "server-response", "rpcId": "test", "result": ["ok": true, "value": ["data": NSNull()]], "attachments": [["path": ["data"], "codec": "bytes", "part": "file"]]]
        var body = Data("--fixture\r\nContent-Disposition: form-data; name=\"metadata\"\r\n\r\n".utf8)
        body.append(try JSONSerialization.data(withJSONObject: metadata))
        body.append(Data("\r\n--fixture\r\nContent-Disposition: form-data; name=\"file\"\r\n\r\n".utf8)); body.append(bytes)
        body.append(Data("\r\n--fixture--\r\n".utf8))
        let envelope = try BinaryRPC.decode(body, contentType: "multipart/form-data; boundary=\"fixture\"")
        let value = (envelope["result"] as? [String: Any])?["value"] as? [String: Any]
        let decoded = try BinaryRPC.bytes(value?["data"])
        let base64 = try BinaryRPC.bytes(bytes.base64EncodedString())
        #expect(decoded == bytes && base64 == bytes)
        #expect(throws: BinaryRPCFailure.self) { _ = try BinaryRPC.decode(body, contentType: "multipart/form-data; boundary=wrong") }
        #expect(throws: BinaryRPCFailure.self) { _ = try BinaryRPC.bytes([256]) }
        let change = TextChange(before: "alpha\nbeta", after: "alpha\ngamma")
        #expect(change.lines == [" alpha", "-beta", "+gamma"])
        #expect(TextChange(before: nil, after: "new").lines == ["+new"])
    }
}
