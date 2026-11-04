// SPDX-License-Identifier: AGPL-3.0-or-later
// Phone control state and tool dispatch; native port of
// 原 Flutter 版 lib/phone_ios/phone_ios_state.dart.
import DSHClient
import DSHPhone
import DSHRuntime
import Foundation
import Observation

struct PhonePrompt: Identifiable, Equatable {
    enum Choice { case reject, once, task }
    let id: Int
    let name: String
    let summary: String
    let allowTask: Bool
}

/// Launch data handed to the runtime worker (engine launch hook).
private final class LaunchBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: PhoneGuestFiles.Launch?
    func set(_ launch: PhoneGuestFiles.Launch?) { lock.withLock { value = launch } }
    func get() -> PhoneGuestFiles.Launch? { lock.withLock { value } }
}

@MainActor
@Observable
final class PhoneController {
    private static let pref = "phone_ios.v1."

    private(set) var enabled: Bool
    private(set) var mode: ConfirmMode
    private(set) var shortcuts: Set<String>
    private(set) var prompt: PhonePrompt?
    private(set) var busy = false
    private(set) var capabilities: [String: String] = [:]
    private(set) var lastError: String?
    private(set) var available = true

    private let executor: PhoneExecutor
    private let runtime: any EngineControlling
    private let safety = PhoneSafety()
    private var server: PhoneBridgeServer?
    private var catalog: PhoneCatalog?
    private let launch = LaunchBox()
    private var approval: CheckedContinuation<PhonePrompt.Choice, Never>?
    #if DEBUG
    /// Test-only: the current bridge endpoint, for the in-app loopback self-test.
    @ObservationIgnored var debugConfig: PhoneBridgeServer.LaunchConfig?
    var debugBridgeEvents: [String] { server?.diagnostics ?? [] }
    @ObservationIgnored var debugTrace: [String] = []
    #endif
    @ObservationIgnored private var serial = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var turn = 0
    private var calling = false
    private var foreground = true
    private var running: [String: Int] = [:]
    private let prefs = UserDefaults.standard

    init(runtime: any EngineControlling, executor: PhoneExecutor) {
        self.runtime = runtime
        self.executor = executor
        enabled = prefs.bool(forKey: Self.pref + "enabled")
        mode = ConfirmMode(rawValue: prefs.string(forKey: Self.pref + "mode") ?? "") ?? .ask
        shortcuts = Set((prefs.stringArray(forKey: Self.pref + "shortcuts") ?? []).filter(Self.validShortcut).prefix(32))
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-dsh-phone-smoke") { enabled = true; mode = .always }
        #endif
        do {
            let catalog = try PhoneCatalog.bundled()
            self.catalog = catalog
            server = PhoneBridgeServer(mcp: McpServer(catalog: catalog) { [weak self] name, args, context in
                guard let self else { return PhoneToolOutput("手机操作连接已断开。", isError: true) }
                return await self.call(name, args, context)
            })
        } catch {
            available = false; lastError = (error as? PhoneError)?.code ?? "E_PHONE_CATALOG"
        }
    }

    /// Core installs this hook on the runtime; the worker only captures the locked launch box.
    var runtimeLaunchHook: RuntimeLaunchHook {
        let box = launch
        return RuntimeLaunchHook(
            prepare: { safe in
                // Safe mode never mounts the overlay; a stale config is always removed.
                guard !safe, let value = box.get() else { try PhoneGuestFiles.prepare(nil); return [] }
                try PhoneGuestFiles.prepare(value)
                return [PhoneGuestFiles.patch]
            },
            cleanup: { try PhoneGuestFiles.prepare(nil) })
    }

    // MARK: Engine lifecycle

    /// Call before every engine start: (re)starts the loopback bridge with a fresh token.
    func beforeEngineStart() async {
        #if DEBUG
        debugTrace.append("beforeEngineStart")
        #endif
        await engineStopped()
        guard enabled, available, let server,
              let relay = Self.resource("relay", "cjs"), let patch = Self.resource("phone.patch", "yml") else { return }
        executor.configure(enabled: true, shortcuts: shortcuts, stopTitle: String(localized: "Stop"))
        do {
            let config = try await server.start()
            #if DEBUG
            debugConfig = config
            #endif
            launch.set(PhoneGuestFiles.Launch(configJSON: config.json, relay: relay, patch: patch))
        } catch {
            lastError = (error as? PhoneError)?.code ?? "E_PHONE_LISTEN"
        }
    }

    func engineStopped() async {
        #if DEBUG
        debugTrace.append("engineStopped")
        #endif
        generation += 1
        launch.set(nil)
        safety.revoke(); running.removeAll(); reject()
        await server?.stop()
        executor.cancelDeferred()
    }

    func setEnabled(_ value: Bool) async {
        guard !busy, value != enabled else { return }
        if value && !available { return }
        busy = true; lastError = nil
        defer { busy = false }
        enabled = value
        prefs.set(value, forKey: Self.pref + "enabled")
        executor.configure(enabled: value, shortcuts: shortcuts, stopTitle: String(localized: "Stop"))
        // Restart the engine so the overlay is mounted or removed.
        let phase = await runtime.status().phase
        guard phase == .running || phase == .starting else { await engineStopped(); return }
        do {
            try await runtime.stop()
            await beforeEngineStart()
            try await runtime.start()
        } catch {
            lastError = (error as? RuntimeError)?.code ?? "E_PHONE_RESTART"
        }
    }

    func setMode(_ value: ConfirmMode) {
        mode = value
        prefs.set(value.rawValue, forKey: Self.pref + "mode")
        safety.revoke()
    }

    static func validShortcut(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespaces) == name && !name.isEmpty && name.count <= 128
            && !name.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }

    /// Settings UI only; never exposed through MCP.
    @discardableResult
    func setShortcuts(_ names: Set<String>) -> Bool {
        guard names.count <= 32, names.allSatisfy(Self.validShortcut) else { return false }
        shortcuts = names
        prefs.set(Array(names).sorted(), forKey: Self.pref + "shortcuts")
        executor.configure(enabled: enabled, shortcuts: names, stopTitle: String(localized: "Stop"))
        safety.revoke()
        return true
    }

    func refreshCapabilities() async { capabilities = await executor.capabilities() }

    func setForeground(_ value: Bool) {
        foreground = value
        if !value {
            safety.revoke()
            if prompt?.name != "handoff" { reject() }
        } else {
            Task { await refreshCapabilities() }
        }
    }

    /// Host `api-session/status` edges: the only source of task scope.
    func sessionStatus(_ sessionId: String, running isRunning: Bool) {
        if isRunning { turn += 1; running[sessionId] = turn } else { running[sessionId] = nil; reject() }
        safety.revoke()
    }

    /// The Host connection changed: no task scope survives it.
    func hostConnectionChanged() { running.removeAll(); safety.revoke(); reject() }

    func handleURL(_ url: URL) -> Bool { executor.receive(url) }

    // MARK: Confirmation

    func answer(_ id: Int, _ choice: PhonePrompt.Choice) {
        guard prompt?.id == id else { return }
        let waiter = approval
        approval = nil; prompt = nil
        waiter?.resume(returning: choice)
    }

    private func reject() {
        let waiter = approval
        approval = nil; prompt = nil
        waiter?.resume(returning: .reject)
    }

    private func confirm(_ name: String, _ args: [String: JSONValue], allowTask: Bool) async -> PhonePrompt.Choice {
        guard foreground else { return .reject }
        reject()
        serial += 1
        let id = serial
        // Shown locally only; clipboard values are never displayed.
        let summary: String
        if name == "clipboard" {
            summary = (args["get"]?.bool) == true ? String(localized: "Read text from the clipboard")
                                                     : String(localized: "Write text to the clipboard")
        } else if let data = try? Self.argumentsData(args) {
            summary = String(decoding: data, as: UTF8.self)
        } else {
            summary = ""
        }
        prompt = PhonePrompt(id: id, name: name, summary: summary, allowTask: allowTask && name != "handoff")
        let timeout = name == "handoff" ? 600.0 : 120.0
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if self?.prompt?.id == id { self?.reject() }
        }
        return await withCheckedContinuation { approval = $0 }
    }

    // MARK: Tool dispatch

    private var scope: String? {
        running.count == 1 ? "\(running.first!.key):\(running.first!.value)" : nil
    }

    func call(_ name: String, _ arguments: ToolArguments, _ context: PhoneCallContext) async -> PhoneToolOutput {
        let args = JSONValue(arguments.values).object ?? [:]
        if context.cancelled { return PhoneToolOutput("手机操作连接已断开。", isError: true) }
        if calling { return PhoneToolOutput("正在等待另一个手机操作，请稍后再试。", isError: true) }
        guard enabled else { return PhoneToolOutput("手机控制已关闭，请用户在 App 设置中开启。", isError: true) }
        guard foreground else { return PhoneToolOutput("App 当前不在前台。请用户返回 App 后重试。", isError: true) }
        calling = true
        defer { calling = false }
        let ticket = generation
        let taskScope = scope
        let listener = context.onCancel { [weak self] in Task { @MainActor in
            self?.reject(); self?.executor.cancelDeferred()
        } }
        defer { context.removeListener(listener) }

        let policy = safety.check(name: name, args: arguments.values, mode: mode, shortcuts: shortcuts, trustedScope: taskScope)
        if let denied = policy.denied { return PhoneToolOutput(denied, isError: true) }
        if policy.confirm {
            let choice = await confirm(name, args, allowTask: policy.allowTask)
            if choice == .reject { return PhoneToolOutput("用户拒绝或确认已过期。请停止该操作，不要换一种方式绕过。", isError: true) }
            if choice == .task, let taskScope, taskScope == scope, policy.allowTask { safety.waive(taskScope) }
        }
        if context.cancelled || ticket != generation || !enabled || !foreground {
            return PhoneToolOutput("手机操作已取消，请回到 App 后重试。", isError: true)
        }
        if name == "shortcut", let shortcut = args["name"]?.string, !shortcuts.contains(shortcut) {
            return PhoneToolOutput("该快捷指令已移出白名单。", isError: true)
        }
        if name == "handoff" { return PhoneToolOutput("用户已选择继续。请继续任务；无法观察用户操作结果，请勿臆测。") }

        let result = await executor.run(name, args)
        if result.ok, name == "shortcut", let shortcut = args["name"]?.string { safety.shortcutCompleted(shortcut) }
        lastError = result.ok ? nil : "E_PHONE_ACTION"
        await refreshCapabilities()
        var after: (@Sendable () async -> Void)?
        if let jump = result.deferred {
            after = { @Sendable [weak self] in
                // The reply has flushed to the relay before the app jump.
                try? await Task.sleep(nanoseconds: 350_000_000)
                await MainActor.run { [weak self] in
                    guard let controller = self else { return }
                    if !context.cancelled, ticket == controller.generation, controller.enabled { controller.executor.commitJump(jump) }
                }
            }
        }
        return PhoneToolOutput(result.text, isError: !result.ok, afterSend: after)
    }

    private static func argumentsData(_ args: [String: JSONValue]) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(args)
    }

    private static func resource(_ name: String, _ ext: String) -> String? {
        Bundle.main.url(forResource: name, withExtension: ext).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}
