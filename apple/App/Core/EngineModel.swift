// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHRuntime
import Foundation
import Observation

/// UI state for the local engine. Mirrors RuntimeEngine events; holds no credentials.
@MainActor
@Observable
final class EngineModel {
    private(set) var status = RuntimeStatus()
    private(set) var progress: RuntimeProgress?
    private(set) var logs: [RuntimeLogEntry] = []
    private(set) var busy = false
    private(set) var actionError: String?
    /// 「打开 App 时自动启动」.
    var autoStart = UserDefaults.standard.object(forKey: "engine.autoStart") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoStart, forKey: "engine.autoStart") }
    }

    let runtime: any EngineControlling
    private let phone: any PhoneControlling

    init(runtime: any EngineControlling, phone: any PhoneControlling) {
        self.runtime = runtime
        self.phone = phone
        runtime.onEvent = { [weak self] event in self?.apply(event) }
        #if DEBUG
        if !AppLaunchPolicy.isUnitTestHost, ProcessInfo.processInfo.arguments.contains("-dsh-smoke") { Task { await smokeTest() } }
        // `-dsh-dump-log`: the engine log tail, to Documents/engine-log.txt every 5 s (redacted).
        if ProcessInfo.processInfo.arguments.contains("-dsh-dump-log") {
            Task {
                while true {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    let text = (await runtime.logTail(lines: 300)).joined(separator: "\n")
                        .replacingOccurrences(of: #"token=[A-Za-z0-9._~%-]+"#, with: "token=***", options: .regularExpression)
                    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("engine-log.txt")
                    try? text.write(to: url, atomically: true, encoding: .utf8)
                }
            }
        }
        #endif
    }

    #if DEBUG
    /// Simulator smoke test: install → start → running → stop, results in Documents/smoke.json.
    /// Records timings and state only; never the launch token.
    private func smokeTest() async {
        var result = SmokeReport()
        func save() {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("smoke.json")
            if let data = try? result.data() {
                try? data.write(to: url, options: .atomic)
            }
        }
        func waitFor(_ phases: Set<RuntimePhase>, seconds: Double) async -> Bool {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                if phases.contains(await runtime.status().phase) { return true }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            return false
        }
        do {
            _ = await waitFor([.installed, .notInstalled, .error], seconds: 120)
            var began = Date()
            try await runtime.install()
            result.set("installMs", Int(Date().timeIntervalSince(began) * 1000))
            began = Date()
            try await runtime.start()
            let running = await waitFor([.running], seconds: 180)
            result.set("startMs", Int(Date().timeIntervalSince(began) * 1000))
            result.set("running", running)
            result.set("connection", await runtime.connection() != nil)
            try await runtime.stop()
            result.set("stoppedPhase", await runtime.status().phase.rawValue)
            result.set("portReleased", RuntimeEngine.portAvailable())
            let snapshot = await runtime.testProcessSnapshot()
            result.set("processesAfterStop", snapshot.processes.map { $0["pid"]?.intValue ?? -1 })
            began = Date()
            try await runtime.start()
            result.set("restartRunning", await waitFor([.running], seconds: 180))
            result.set("restartMs", Int(Date().timeIntervalSince(began) * 1000))
            result.set("result", "PASS")
        } catch {
            result.set("result", "FAIL")
            result.set("error", (error as? RuntimeError)?.code ?? "E_RUNTIME_IO")
            result.set("phase", await runtime.status().phase.rawValue)
        }
        save()
    }
    #endif

    private func apply(_ event: RuntimeEvent) {
        switch event {
        case .status(let value):
            status = value
            // Engine crashed: drop pending phone prompts. Normal stops clean up in stop();
            // every start re-prepares the bridge first, so no stale state survives.
            if value.phase == .error { Task { await phone.engineStopped() } }
            if value.phase != .installing { progress = nil }
        case .progress(let value):
            progress = value
        case .logs(let batch):
            logs.append(contentsOf: batch)
            if logs.count > 300 { logs.removeFirst(logs.count - 300) }
        }
    }

    /// Same as the Flutter onboarding's local default: install if needed, then start.
    func prepareOnLaunch(force: Bool = false) {
        guard !AppLaunchPolicy.isUnitTestHost else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-dsh-smoke") && !force { return }
        #endif
        perform { [autoStart, phone] runtime in
            let status = await runtime.status() // Queued after the engine's cold-start recovery.
            guard !status.restartRequired else { return }
            if !force && !autoStart && status.phase != .notInstalled { return }
            if status.phase == .notInstalled { try await runtime.install() }
            if [.installed, .notInstalled].contains(await runtime.status().phase) {
                await phone.beforeEngineStart()
                try await runtime.start()
            }
        }
    }

    func install() { perform { try await $0.install() } }
    func start() { perform { [phone] in await phone.beforeEngineStart(); try await $0.start() } }
    func startSafe() { perform { [phone] in await phone.beforeEngineStart(); try await $0.start(mode: .safe) } }
    /// Safe mode stays on for every later start until the user asks for normal mode
    /// (same as Android SafeMode). Normal mode then runs on probation.
    var safeModeOn: Bool { status.safeState == "on" }
    func startNormal() {
        perform { [phone] runtime in
            let phase = await runtime.status().phase
            if phase == .running || phase == .starting { try await runtime.stop() }
            await phone.beforeEngineStart()
            try await runtime.start(mode: .normal)
        }
    }
    func stop() { perform { [phone] in try await $0.stop(); await phone.engineStopped() } }
    func restart() {
        perform { [phone] runtime in
            try await runtime.stop()
            await phone.beforeEngineStart()
            try await runtime.start()
        }
    }
    func setAutoSafe(_ enabled: Bool) { Task { await runtime.setAutoSafe(enabled) } }
    func reset() { perform { try await $0.reset() } }

    private func perform(_ action: @escaping (any EngineControlling) async throws -> Void) {
        guard !busy else { return }
        busy = true; actionError = nil
        Task {
            defer { busy = false }
            do { try await action(runtime) }
            catch { actionError = (error as? RuntimeError)?.code ?? "E_RUNTIME_IO" }
        }
    }
}
