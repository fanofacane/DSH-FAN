// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import DSHClient
import Foundation
import Photos

struct FeatureSmokeDependencies {
    let runtime: any EngineControlling
    let preferences: AppPreferences
    let notifications: TaskNotifications
    let photoLibrary: PHPhotoLibrary?
}

/// A reference keeps incremental report writes intact across registered async cases.
@MainActor final class FeatureSmokeContext {
    let dependencies: FeatureSmokeDependencies
    private let name: String
    private var report = SmokeReport()
    init(name: String, dependencies: FeatureSmokeDependencies) {
        self.name = name; self.dependencies = dependencies
        report.set("task", name); report.set("result", "RUNNING")
    }
    subscript(_ key: String) -> JSONValue? { report[key] }
    func set<Value: Encodable>(_ key: String, _ value: Value) { report.set(key, value) }
    func save() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("feature-" + name + ".json")
        if let data = try? report.data() { try? data.write(to: url, options: .atomic) }
    }
}

@MainActor enum FeatureSmokeRegistry {
    typealias Run = @MainActor (AppSession, FeatureSmokeContext) async throws -> Void
    static let cases: [String: Run] = [
        "t1": { try await $0.smokeT1($1) },
        "t2": { try await $0.smokeT2($1) },
        "t3": { try await $0.smokeT3($1) },
        "t4": { try await $0.smokeT4($1) },
        "t5": { try await $0.smokeT5($1) },
        "t6": { try await $0.smokeT6($1) },
        "t7": { try await $0.smokeT7($1) },
        "t8": { try await $0.smokeT8($1) },
        "t10": { try await $0.smokeT10($1) },
        "t11": { try await $0.smokeT11($1) },
        "t12": { try await $0.smokeT12($1) },
        "t13": { try await $0.smokeT13($1) },
        "t14": { try await $0.smokeT14($1) },
        "store": { try await $0.smokeStore($1) },
        "t15": { try await $0.smokeT15($1) },
    ]
}

extension AppSession {
    static var featureSmokeName: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-dsh-feature-smoke"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
    func runFeatureSmoke(_ name: String, dependencies: FeatureSmokeDependencies) async {
        let result = FeatureSmokeContext(name: name, dependencies: dependencies)
        result.save()
        do {
            guard let run = FeatureSmokeRegistry.cases[name] else { throw DSHError("E_UNKNOWN_SMOKE") }
            try await run(self, result)
            result.set("result", "PASS")
        } catch { result.set("result", "FAIL"); result.set("code", (error as? DSHError)?.code ?? "E_TRANSPORT") }
        result.save()
    }
    func smokeWait(seconds: Double = 20, _ predicate: () -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !predicate(), Date() < end { try await Task.sleep(nanoseconds: 100_000_000) }
        guard predicate() else { throw DSHError("E_SMOKE_TIMEOUT") }
    }
}
#endif
