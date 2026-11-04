// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing
@testable import DSHClient
struct SettingsTests {
    @Test func contracts() {
        let schema = EngineSchema(["uid": "root", "refs": [
            "root": ["type": "object", "dict": ["enabled": "bool", "optional": "union", "key": "wrapper"]],
            "bool": ["type": "boolean", "meta": ["default": true]],
            "null": ["type": "const", "value": NSNull()],
            "number": ["type": "number"],
            "union": ["type": "union", "list": ["null", "number"]],
            "wrapper": ["type": "transform", "inner": "string", "meta": ["role": "secret"]],
            "string": ["type": "string"]
        ]])
        let fields = schema.fields(schema.root)
        #expect(fields.count == 3)
        #expect(fields["optional"]?["type"] as? String == "number")
        #expect((fields["key"]?["meta"] as? [String: Any])?["role"] as? String == "secret")
        #expect((schema.defaultValue(schema.root) as? [String: Any])?["enabled"] as? Bool == true)
        let section = EngineNamespace(["ns": "fixture", "secrets": [["path": ["services", "0", "key"], "set": true]]])
        #expect(section.secretPaths == [["services", "0", "key"]])
    }
}
