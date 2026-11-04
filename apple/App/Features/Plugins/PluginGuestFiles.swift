// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHRuntime

/// Called only on the runtime worker, using the guest VFS just like the phone overlay.
enum PluginGuestFiles {
    static let patch = "/opt/dsh-app/bundled-plugins.patch.yml"
    static func prepare(_ plugins: [PluginDescriptor], gate: any PluginGate, safeMode: Bool) throws -> [String] {
        let activeGate: any PluginGate = safeMode ? LocalPluginGate() : gate
        guard let text = try PluginPatch.contents(for: plugins, gate: activeGate) else {
            try cleanup(); return []
        }
        guard GuestFiles.mkdir("/opt/dsh-app", mode: 0o755), GuestFiles.write(patch, text, mode: 0o644) else {
            throw RuntimeError("E_BUNDLED_PLUGIN_PATCH")
        }
        return [patch]
    }
    static func cleanup() throws {
        guard GuestFiles.unlink(patch) else { throw RuntimeError("E_BUNDLED_PLUGIN_PATCH") }
    }
}
