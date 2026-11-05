// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/test/engine_settings/ and app/test/safe_mode/ golden fixtures.
#if DEBUG
import DSHClient
import DSHRuntime
import Foundation

@MainActor enum DebugEngineSettings {
    static var sections: [EngineNamespace] {
        let fixture = DebugPageRegistry.argument("-dsh-screen-fixture")
        let writable = fixture != "read-only" && fixture != "locked"
        return [
            section("bash-sandbox", [
                "timeoutMs": number(60_000, 1_000, 300_000, step: 1_000),
                "maxOutputBytes": number(65_536, 1_024, 1_048_576),
                "maxTimeoutMs": number(300_000, 1_000, 1_800_000, step: 1_000),
                "maxSpillBytes": number(10_485_760, 1_024, 50_331_648),
                "graceMs": number(1_500, 0, 10_000, step: 100),
            ], base: ["timeoutMs": 60_000, "maxOutputBytes": 65_536, "maxTimeoutMs": 600_000,
                       "maxSpillBytes": 67_108_864, "graceMs": 3_000], user: ["timeoutMs": 90_000], writable: writable),
            section("agent-loop", ["maxParallelToolCalls": number(4, 1, 32)],
                    base: ["maxParallelToolCalls": 4], user: ["maxParallelToolCalls": 3], writable: writable),
            section("subagent", ["maxDepth": number(2, 0, 10), "maxActive": number(4, 1, 16)],
                    base: ["maxDepth": 2, "maxActive": 4], writable: writable),
            section("subagent-model-selection-settings", ["enabled": boolean, "allowedModels": [
                        "type": "array", "inner": ["type": "object", "dict": ["provider": string, "model": string]]
                    ]], base: ["enabled": true, "allowedModels": [["provider": "deepseek-api", "model": "deepseek-v4-flash"]]], writable: writable),
            section("ui-settings", ["showToolOutput": boolean, "showThinking": boolean, "language": string],
                    base: ["showToolOutput": true, "showThinking": true, "language": "system"], writable: writable),
            section("web", ["searchProvider": string, "fetchProvider": string],
                    base: ["searchProvider": "deepseek-official", "fetchProvider": "http"],
                    user: fixture == "api" ? ["searchProvider": "deepseek-search-api", "fetchProvider": "deepseek-fetch-api"] : [:],
                    writable: writable),
            section("web-search-deepseek", ["apiKey": secret, "baseURL": string, "maxUses": number(5, 1, 20)],
                    base: ["baseURL": "https://api.deepseek.com", "maxUses": 5], writable: writable),
            section("web-deepseek-api", ["apiKey": secret, "baseURL": string, "count": number(5, 1, 20)],
                    base: ["baseURL": "https://api.deepseek.com", "count": 5], writable: writable),
            section("media", ["services": ["type": "array", "inner": service], "defaults": ["type": "dict", "inner": string],
                              "limits": ["type": "object", "dict": ["maxConcurrent": number(2, 1, 8)]]],
                    base: ["services": [["id": "images", "label": "Example images", "enabled": true]],
                           "defaults": ["image": "images"], "limits": ["maxConcurrent": 2]], writable: writable),
        ]
    }

    static var status: RuntimeStatus? {
        guard DebugPageRegistry.usesFixture else { return nil }
        var value = RuntimeStatus()
        switch DebugPageRegistry.argument("-dsh-screen-fixture") {
        case "running", "safe", "failed", "normal":
            let fixture = DebugPageRegistry.argument("-dsh-screen-fixture")
            value.phase = fixture == "failed" ? .error : .running
            value.installedVersion = "0.2.1"
            value.dshVersion = "0.2.1"
            value.nodeVersion = "24.0.0"
            value.safeState = fixture == "safe" ? "on" : "off"
            value.mode = fixture == "safe" ? .safe : .normal
            if fixture == "failed" { value.errorCode = "E_EXIT" }
        default:
            value.phase = .notInstalled
        }
        return value
    }

    private static let string: [String: Any] = ["type": "string"]
    private static let boolean: [String: Any] = ["type": "boolean"]
    private static let secret: [String: Any] = ["type": "string", "meta": ["role": "secret"]]
    private static let service: [String: Any] = ["type": "object", "dict": ["id": string, "label": string, "enabled": boolean]]

    private static func number(_ defaultValue: Int, _ min: Int, _ max: Int, step: Int = 1) -> [String: Any] {
        ["type": "number", "meta": ["default": defaultValue, "min": min, "max": max, "step": step]]
    }

    private static func section(_ id: String, _ fields: [String: [String: Any]], base: [String: Any],
                                user: [String: Any] = [:], writable: Bool) -> EngineNamespace {
        EngineNamespace(["ns": id, "revision": 1, "schema": ["type": "object", "dict": fields],
                         "value": base.merging(user) { _, override in override }, "base": base, "user": user,
                         "secrets": fields["apiKey"] == nil ? [] : [["path": ["apiKey"], "set": false]]],
                        writable: writable)
    }
}
#endif
