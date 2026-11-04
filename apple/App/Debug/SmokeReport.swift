// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import DSHClient
import Foundation

/// Heterogeneous diagnostic fields are JSON, and every inserted value must be Encodable.
struct SmokeReport: Encodable {
    private var fields: [String: JSONValue] = [:]
    subscript(_ key: String) -> JSONValue? { fields[key] }
    mutating func set<Value: Encodable>(_ key: String, _ value: Value) {
        do { fields[key] = try JSONValue(data: JSONEncoder().encode(value)) }
        catch { fields["result"] = "FAIL"; fields["error"] = "E_SMOKE_JSON" }
    }
    func encode(to encoder: Encoder) throws { try fields.encode(to: encoder) }
    func data() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
#endif
