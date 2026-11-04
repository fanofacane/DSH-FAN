// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHRuntime
import Foundation
import Testing
@testable import DSH

struct PluginGateTests {
    private let plugins = [
        PluginDescriptor(id: "b", engineRowID: "bundled-b", title: "B", settingsEntry: nil),
        PluginDescriptor(id: "a", engineRowID: "bundled-a", title: "A", settingsEntry: "a-settings"),
    ]

    @Test func productionGateAlwaysDisablesBundledPlugins() throws {
        #expect(plugins.allSatisfy { !$0.defaultEnabled && !LocalPluginGate().isEnabled($0) })
        #expect(PluginCatalog.bundled.isEmpty)
        #expect(try PluginPatch.contents(for: [], gate: LocalPluginGate()) == nil)
        #expect(try PluginPatch.contents(for: plugins, gate: LocalPluginGate()) == "# App-owned bundled plugin switches.\n- id: \"bundled-a\"\n  disabled: true\n- id: \"bundled-b\"\n  disabled: true\n")
    }

    @Test func selectedSwitchesProduceStableRowsAndCannotEnableManagers() throws {
        let managers = [
            PluginDescriptor(id: "pm", engineRowID: "plugin-manager", title: "manager", settingsEntry: nil),
            PluginDescriptor(id: "tm", engineRowID: "tool-plugin-manager", title: "tool", settingsEntry: nil),
        ]
        let gate = TestPluginGate(enabled: ["b", "pm", "tm"])
        let catalog = plugins + managers
        let patch = try PluginPatch.contents(for: catalog, gate: gate)
        #expect(patch == "# App-owned bundled plugin switches.\n- id: \"bundled-a\"\n  disabled: true\n- id: \"bundled-b\"\n  disabled: false\n- id: \"plugin-manager\"\n  disabled: true\n- id: \"tool-plugin-manager\"\n  disabled: true\n")
        #expect(try PluginPatch.contents(for: Array(catalog.reversed()), gate: gate) == patch)
    }

    @Test func rowIDsAreQuotedAndDuplicatesRejected() throws {
        let row = "row\"\n- id: other"
        let descriptor = PluginDescriptor(id: "quoted", engineRowID: row, title: "Q", settingsEntry: nil)
        let patch = try #require(try PluginPatch.contents(for: [descriptor], gate: LocalPluginGate()))
        let idLine = try #require(patch.split(separator: "\n").first { $0.hasPrefix("- id: ") })
        let quoted = String(idLine.dropFirst(6))
        #expect(try JSONDecoder().decode(String.self, from: Data(quoted.utf8)) == row)
        #expect(patch.split(separator: "\n").count == 3)
        do {
            _ = try PluginPatch.contents(for: [descriptor, descriptor], gate: LocalPluginGate())
            Issue.record("duplicate engine rows must be rejected")
        } catch let error as RuntimeError { #expect(error.code == "E_PLUGIN_CATALOG") }
    }
}

/// Test-only switches; production exposes no settings or remote implementation.
private struct TestPluginGate: PluginGate {
    let enabled: Set<String>
    func isEnabled(_ plugin: PluginDescriptor) -> Bool { enabled.contains(plugin.id) }
}
