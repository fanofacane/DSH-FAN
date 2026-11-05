// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing
@testable import DSH
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

@MainActor struct EngineDraftTests {
    @Test func typedRulesUseNumericBoundsAndNullableBranches() {
        let schema = EngineSchema([:])
        let number: [String: Any] = ["type": "number", "meta": ["min": 1, "max": 3, "step": 0.5]]
        let optional = schema.effective(["type": "union", "list": [number, ["type": "const", "value": NSNull()]]])
        let field = EngineFieldRules(schema: schema, node: optional)
        #expect(field.valid(2.5) && field.valid(NSNull()))
        #expect(!field.valid(3.5) && !field.valid(1.25) && !field.valid(true))
        let sequence = EngineFieldRules(schema: schema, node: ["type": "array", "inner": number, "meta": ["min": 1, "max": 2]])
        #expect(sequence.valid([1, 3]))
        #expect(!sequence.valid([]) && !sequence.valid([1, 2, 3]))
    }

    @Test func draftsResetToInheritedValueAndNeverOverwriteSecretSlots() {
        let section = EngineNamespace([
            "ns": "example", "revision": 9, "value": ["timeout": 12, "services": [["name": "one"]]],
            "user": ["timeout": 12], "base": ["timeout": 6],
            "secrets": [["path": ["services", "0", "key"], "set": false]]
        ])
        let model = EngineFormModel(section)
        #expect(section.secretPaths.isEmpty && section.secretFields == [["services", "0", "key"]])
        model.set(["services"], [])
        #expect(!model.hasEdits && model.error == "E_SETTINGS_HIDDEN_SECRET")
        model.set(["services", "0", "name"], "two")
        #expect(model.value(["services", "0", "name"]) as? String == "two")
        model.restore(["timeout"])
        #expect(model.resets == [["timeout"]] && model.value(["timeout"]) as? Int == 6)
        model.set(["timeout"], 12)
        #expect(model.resets.isEmpty && model.changes[["timeout"]] == nil)
    }

    @Test func writesUseRevisionAndKeepDraftOnHostRejection() async throws {
        let document: [String: Any] = ["type": "object", "dict": ["limit": ["type": "number"]]]
        let rig = StoreRig(failures: ["settings/mutate": DSHError("settings/conflict")])
        defer { rig.stop() }
        await rig.app.connection.connect()
        let model = EngineFormModel(EngineNamespace(["ns": "example", "revision": 9, "value": ["limit": 1],
                                                     "schema": document]), generation: rig.app.connection.generation)
        model.set(["limit"], 2)
        await model.save(rig.app)
        let call = try #require(rig.fixture.calls.first { $0.endpoint == "settings/mutate" })
        #expect(call.args["expectedRevision"] as? Int == 9)
        #expect(model.error == "settings/conflict" && model.hasEdits)
        rig.app.connection.disconnect()
        await model.save(rig.app)
        #expect(model.error == "E_SETTINGS_HOST_CHANGED")
        #expect(rig.fixture.calls.filter { $0.endpoint == "settings/mutate" }.count == 1)
    }

    @Test func mediaCataloguePrefersCurrentKeyAndAcceptsLegacyHost() {
        func namespace(_ extra: [String: Any]) -> EngineNamespace {
            EngineNamespace(["ns": "renamed", "schema": ["type": "object", "dict": [
                "services": ["type": "transform", "inner": ["type": "array"], "meta": ["extra": extra]]
            ]]])
        }
        #expect(mediaCatalog(in: namespace(["dsh-go/media/catalog": ["version": 1]]))?["version"] as? Int == 1)
        let both = namespace(["dsh-go/media/catalog": ["version": 1], "dsh-fan/media/catalog": ["version": 2]])
        #expect(mediaCatalog(in: both)?["version"] as? Int == 2)
    }
}
