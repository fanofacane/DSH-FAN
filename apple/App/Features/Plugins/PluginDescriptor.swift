// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHRuntime
import Foundation

/// Metadata for code already distributed inside the App. No installation or remote configuration.
struct PluginDescriptor: Sendable {
    let id: String
    let engineRowID: String
    let title: String
    /// The id of a SettingsEntry, when a bundled plugin has its own settings page.
    let settingsEntry: String?
    let defaultEnabled = false
}

protocol PluginGate: Sendable {
    func isEnabled(_ plugin: PluginDescriptor) -> Bool
}

struct LocalPluginGate: PluginGate {
    func isEnabled(_ plugin: PluginDescriptor) -> Bool { false }
}

enum PluginCatalog {
    /// No optional bundled plugins are registered yet. Existing engine / phone services stay as before.
    static let bundled: [PluginDescriptor] = []
}

enum PluginPatch {
    private static let prohibitedRows: Set<String> = ["plugin-manager", "tool-plugin-manager"]
    static func contents(for plugins: [PluginDescriptor], gate: any PluginGate) throws -> String? {
        guard !plugins.isEmpty else { return nil }
        guard Set(plugins.map(\.engineRowID)).count == plugins.count else { throw RuntimeError("E_PLUGIN_CATALOG") }
        let encoder = JSONEncoder()
        let rows = try plugins.sorted { $0.engineRowID < $1.engineRowID }.map { plugin in
            // JSON string quoting is valid YAML and prevents row ids from changing the patch structure.
            let id = String(decoding: try encoder.encode(plugin.engineRowID), as: UTF8.self)
            let enabled = !prohibitedRows.contains(plugin.engineRowID) && gate.isEnabled(plugin)
            return "- id: \(id)\n  disabled: \(enabled ? "false" : "true")\n"
        }
        return "# App-owned bundled plugin switches.\n" + rows.joined()
    }
}
