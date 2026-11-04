// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHRuntime

/// Compose app overlays without changing DSHRuntime's dependency direction or the mandatory store patch.
enum AppRuntimeHook {
    static func make(phone: RuntimeLaunchHook, plugins: [PluginDescriptor], gate: any PluginGate) -> RuntimeLaunchHook {
        RuntimeLaunchHook(prepare: { safe in
            let phonePatches = try phone.prepare(safe)
            return phonePatches + (try PluginGuestFiles.prepare(plugins, gate: gate, safeMode: safe))
        }, cleanup: {
            try phone.cleanup()
            try PluginGuestFiles.cleanup()
        })
    }
}
