// SPDX-License-Identifier: AGPL-3.0-or-later
// Native (non-Flutter) port of 原 Flutter 版 ios/Runner/Runtime/RuntimeController.swift.
// Lifecycle rules are unchanged: one kernel boot per App process, stop keeps
// PID 1, reset/replace while mounted is deferred to the next cold start.
import Darwin
import Foundation
import ish

public enum RuntimePhase: String, Sendable {
    case notInstalled, installing, installed, starting, running, stopping, error
}

public enum RuntimeMode: String, Sendable { case normal, safe }

public struct RuntimeStatus: Equatable, Sendable {
    public var phase: RuntimePhase = .notInstalled
    public var mode: RuntimeMode = .normal
    /// off / probation / on — mirrors Android SafeMode.
    public var safeState = "off"
    public var strikes = 0
    public var autoSafe = true
    public var errorCode: String?
    /// A reset or replacement is waiting for the next cold start.
    public var restartRequired = false
    public var pendingOperation = false
    public var bundledVersion: String?
    public var installedVersion: String?
    public var dshVersion: String?
    public var nodeVersion: String?
    /// Only set while running. The launch token is never part of the status.
    public var baseURL: URL?
    public init() {}
}

public struct RuntimeProgress: Equatable, Sendable {
    /// verify / extract / configure
    public var step: String
    public var done: Int64
    public var total: Int64
    public var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
}

public struct RuntimeLogEntry: Equatable, Sendable {
    public var seq: Int64
    public var line: String
    /// stdout / stderr / system
    public var stream: String
}

/// Engine connection details for the local DSH client. Keep in memory only.
public struct RuntimeConnection: Sendable {
    public let baseURL: URL
    public let token: String
}

public enum RuntimeEvent: Sendable {
    case status(RuntimeStatus)
    case progress(RuntimeProgress)
    case logs([RuntimeLogEntry])
}

/// Optional launch extension, e.g. the phone-control overlay (stage M4).
/// `prepare` runs after boot and before DSH starts; it returns extra `--patch` files.
/// `cleanup` runs after a successful stop.
public struct RuntimeLaunchHook: Sendable {
    public var prepare: @Sendable (_ safeMode: Bool) throws -> [String]
    public var cleanup: @Sendable () throws -> Void
    public init(prepare: @escaping @Sendable (Bool) throws -> [String], cleanup: @escaping @Sendable () throws -> Void) {
        self.prepare = prepare; self.cleanup = cleanup
    }
}

public final class RuntimeEngine: @unchecked Sendable {
    public static let shared = RuntimeEngine()
    public static let port: UInt16 = 3080

    /// Delivered on the main queue.
    public var onEvent: (@MainActor (RuntimeEvent) -> Void)? {
        get { eventLock.lock(); defer { eventLock.unlock() }; return handler }
        set {
            eventLock.lock(); handler = newValue; let status = lastStatus, progress = lastProgress; eventLock.unlock()
            if let status { deliver(.status(status)) }
            if let progress { deliver(.progress(progress)) }
        }
    }
    public var launchHook: RuntimeLaunchHook?

    // Everything below is owned by `worker`.
    private let worker = DispatchQueue(label: "dsh.runtime", qos: .userInitiated)
    private let kernel = RuntimeKernel()
    private let logs = RuntimeLogs()
    private var installer: RuntimeInstaller?
    private let eventLock = NSLock()
    private var handler: (@MainActor (RuntimeEvent) -> Void)?
    private var lastStatus: RuntimeStatus?
    private var lastProgress: RuntimeProgress?
    private var phase = RuntimePhase.notInstalled
    private var error: String?
    private var token: String?
    private var enginePID: Int32?
    private var launchGeneration = 0
    private var readyAt: Date?
    private var launchAt: Date?
    private var deadline: Date?
    private var fatal = false
    private var mode = RuntimeMode.normal
    private var safeState: String
    private var strikes: Int
    private var autoSafe: Bool
    private let prefs = UserDefaults.standard
    private var timer: DispatchSourceTimer?
    private var progressSentAt = Date.distantPast

    private init() {
        safeState = prefs.string(forKey: "runtime.safeState") ?? "off"
        strikes = prefs.integer(forKey: "runtime.strikes")
        autoSafe = prefs.object(forKey: "runtime.autoSafe") as? Bool ?? true
        worker.async { self.coldStart() }
    }

    // MARK: Public API (all work happens on the runtime worker)

    public func status() async -> RuntimeStatus { await run { self.makeStatus() } }

    /// Base URL and launch token while running; nil otherwise.
    public func connection() async -> RuntimeConnection? {
        await run {
            guard self.phase == .running, let token = self.token else { return nil }
            return RuntimeConnection(baseURL: Self.baseURL, token: token)
        }
    }

    public func install(force: Bool = false, dropKept: Bool = false) async throws {
        try await runThrowing { try self.doInstall(force: force, dropKept: dropKept) }
    }
    /// Boots the kernel on first use, then launches DSH. Returns once launch began;
    /// observe `.status` events for `running`.
    public func start(mode requested: RuntimeMode? = nil, environment: [String: String] = [:]) async throws {
        try await runThrowing { try self.doStart(mode: requested, extraEnv: environment) }
    }
    public func stop() async throws { try await runThrowing { try self.doStop() } }
    /// `keep` groups: uiAndSkills, pluginsAndSettings (same as Android).
    public func reset(keep: [String] = []) async throws { try await runThrowing { try self.doReset(groups: keep) } }
    public func setAutoSafe(_ enabled: Bool) async {
        await run { self.autoSafe = enabled; self.prefs.set(enabled, forKey: "runtime.autoSafe"); self.setPhase(self.phase) }
    }
    static let storePatchPath = "/opt/dsh-app/ios-store.patch.yml"
    /// The iOS app does not download or install code: the plugin manager
    /// (pnpm installs of external bundles, also offered to agents as the
    /// `plugin_manager` tool) stays off. Its tools and the market tools need
    /// this service, so they stay inactive in every agent preset too.
    static let storePatch = """
    # Written by the iOS app on every engine start.
    - id: plugin-manager
      disabled: true
    - id: tool-plugin-manager
      disabled: true

    """
    public func clearFailure() async { await run { self.error = nil; self.setPhase(self.phase) } }
    public func logTail(lines: Int = 500) async -> [String] { await run { self.logs.tail(lines: lines) } }
    public func availableBytes() async -> Int64 { await run { (try? self.installer?.availableBytes()) ?? 0 } }
    /// Fixed local preferences file, read by DSH as shared agent instructions.
    /// VFS access is serialized with lifecycle operations; no host path escape.
    public func replyPreferences() async throws -> String {
        try await run { Result { try self.readReplyPreferences() } }.get()
    }
    public func saveReplyPreferences(_ text: String, expected: String) async throws {
        try await run { Result {
            guard text.utf8.count <= 65536 else { throw RuntimeError("E_PREFERENCES_TOO_LARGE") }
            guard try self.readReplyPreferences() == expected else { throw RuntimeError("E_PREFERENCES_CHANGED") }
            let directory = "/root/.agents", path = directory + "/AGENTS.md"
            let mode = dsh_kernel_mode(directory)
            guard mode == -2 || mode & 0o170000 == 0o040000 else { throw RuntimeError("E_PREFERENCES_PATH") }
            guard mode != -2 || dsh_kernel_mkdir(directory, 0o700) else { throw RuntimeError("E_PREFERENCES_WRITE") }
            let ok = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? dsh_kernel_unlink(path) : dsh_kernel_write_mode(path, text, 0o600)
            guard ok else { throw RuntimeError("E_PREFERENCES_WRITE") }
        } }.get()
    }
    private func readReplyPreferences() throws -> String {
        guard phase == .running, kernel.booted else { throw RuntimeError("E_ENGINE_NOT_RUNNING") }
        let directory = dsh_kernel_mode("/root/.agents")
        if directory == -2 { return "" }
        guard directory & 0o170000 == 0o040000 else { throw RuntimeError("E_PREFERENCES_PATH") }
        let path = "/root/.agents/AGENTS.md", mode = dsh_kernel_mode(path)
        if mode == -2 { return "" }
        guard mode & 0o170000 == 0o100000, let text = dsh_kernel_read_text(path, 65536) else { throw RuntimeError("E_PREFERENCES_READ") }
        return text
    }
    public func manifest() async -> [String: String] {
        await run { (self.installer?.manifest ?? [:]).compactMapValues { "\($0)" } }
    }

    #if DEBUG
    public func testProcessSnapshot() async -> (processes: [[String: NSNumber]], booted: Bool, pending: Bool) {
        await run { (self.kernel.processes, self.kernel.booted, self.installer?.pending == true) }
    }
    #endif

    // MARK: Worker helpers

    private func run<T>(_ body: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in worker.async { continuation.resume(returning: body()) } }
    }
    private func runThrowing(_ body: @escaping () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            worker.async {
                do { try body(); continuation.resume() }
                catch {
                    let code = self.errorCode(error)
                    self.fail(code)
                    continuation.resume(throwing: RuntimeError(code))
                }
            }
        }
    }
    private func deliver(_ event: RuntimeEvent) {
        eventLock.lock(); let callback = handler; eventLock.unlock()
        guard let callback else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { callback(event) } }
    }

    // MARK: Lifecycle (ported 1:1 from RuntimeController)

    private func coldStart() {
        do {
            let value = try RuntimeInstaller(); installer = value
            if value.pending {
                setPhase(.installing)
                try value.finishPending(progress: progress)
                logs.append("[dsh-app] cold recovery complete; kernel not booted", stream: "system")
            }
            setPhase(value.current ? .installed : .notInstalled)
        } catch { fail(errorCode(error)) }
        let timer = DispatchSource.makeTimerSource(queue: worker)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer; timer.resume()
        // No mount/boot here. Only an explicit start() boots the kernel.
    }
    private func errorCode(_ failure: Error) -> String { (failure as? RuntimeError)?.code ?? "E_RUNTIME_IO" }
    private func makeStatus() -> RuntimeStatus {
        var value = RuntimeStatus()
        value.phase = phase; value.mode = mode; value.safeState = safeState
        value.strikes = strikes; value.autoSafe = autoSafe; value.errorCode = error
        value.restartRequired = installer?.pending == true || (kernel.bootAttempted && !kernel.booted)
        value.pendingOperation = installer?.pending == true
        value.bundledVersion = installer?.version
        value.installedVersion = installer?.installedVersion
        value.dshVersion = installer?.manifest["dshVersion"] as? String
        value.nodeVersion = installer?.manifest["nodeVersion"] as? String
        if phase == .running { value.baseURL = Self.baseURL }
        return value
    }
    private func setPhase(_ value: RuntimePhase) {
        phase = value
        let status = makeStatus()
        eventLock.lock()
        lastStatus = status
        if value != .installing { lastProgress = nil }
        eventLock.unlock()
        deliver(.status(status))
    }
    private func fail(_ code: String) {
        error = code; token = nil
        logs.append("[dsh-app] \(code)", stream: "system")
        setPhase(.error)
    }
    private func progress(_ step: String, _ done: Int64, _ total: Int64) {
        let value = RuntimeProgress(step: step, done: done, total: total)
        eventLock.lock(); lastProgress = value; eventLock.unlock()
        let now = Date()
        if now.timeIntervalSince(progressSentAt) >= 0.1 || done == total || done == 0 {
            progressSentAt = now; deliver(.progress(value))
        }
    }
    private func requireInstaller() throws -> RuntimeInstaller {
        guard let installer else { throw RuntimeError("E_MANIFEST") }
        return installer
    }
    private func doInstall(force: Bool, dropKept: Bool) throws {
        let value = try requireInstaller()
        if value.pending { throw RuntimeError("E_RESTART_REQUIRED") }
        if value.current && !force { return }
        if kernel.bootAttempted {
            try value.deferOperation("install", keep: ["root"])
            try doStop(); throw RuntimeError("E_RESTART_REQUIRED")
        }
        if dropKept { try value.discardKept() }
        error = nil; setPhase(.installing)
        let began = Date()
        try value.install(progress: progress)
        logs.append("[dsh-app] runtime installed in \(Int(Date().timeIntervalSince(began) * 1000)) ms", stream: "system")
        setPhase(.installed)
    }
    private func doStart(mode requested: RuntimeMode?, extraEnv: [String: String]) throws {
        let value = try requireInstaller()
        if value.pending { throw RuntimeError("E_RESTART_REQUIRED") }
        if phase == .running || phase == .starting { return }
        guard value.current else { throw RuntimeError("E_NOT_INSTALLED") }
        guard kernel.processes.allSatisfy({ $0["pid"]?.intValue == 1 }) else { throw RuntimeError("E_GUEST_PROCESSES_REMAIN") }
        guard Self.portAvailable() else { throw RuntimeError("EADDRINUSE") }
        if requested == .safe { safeState = "on" }
        if requested == .normal, safeState == "on" { safeState = "probation" }
        mode = safeState == "on" ? .safe : .normal
        prefs.set(safeState, forKey: "runtime.safeState")
        var env = Self.launchEnvironment()
        for (key, text) in extraEnv {
            guard key.range(of: #"^[A-Z_][A-Z0-9_]*$"#, options: .regularExpression) != nil,
                  key.range(of: "(?i)key|token|secret|password|cookie|authorization", options: .regularExpression) == nil,
                  !["NODE_OPTIONS", "LD_PRELOAD", "ISH_NODE_MODE"].contains(key), env[key] == nil,
                  !text.contains("\0") else { throw RuntimeError("E_LAUNCH_ENV") }
            env[key] = text
        }
        var argv = ["/usr/local/bin/dsh"]
        if mode == .safe {
            // With --profile, dsh serves web by default and takes no `web` word.
            argv += ["--profile", "dsh-app-safe", "--patch", "/etc/dsh-app/safe.patch.yml"]
            env["DSH_APP_SAFE_MODE"] = "1"
        } else {
            argv += ["web", "--patch", "/etc/dsh-app/dsh-web.patch.yml"]
        }
        argv += ["--host", "127.0.0.1", "--port", String(Self.port), "--no-open"]
        // Every start runs through a small sh prelude before exec'ing dsh:
        // * Stale writer locks. dsh's atomic-write lock records its holder's PID
        //   and only takes it over when that PID no longer exists. iSH restarts
        //   PIDs from the same small numbers on every boot, so after a force quit
        //   the new dsh often has the dead writer's PID and waits forever
        //   (`timed out waiting for the writer lock at …/.credentials.yaml.lock`).
        //   Nothing else runs in the guest when the engine starts (only PID 1),
        //   so these `<file>.<ext>.lock` files are stale here. (`session.lock`
        //   files are a different, persistent mechanism and stay.)
        // * Safe mode profile: a fresh busybox copy of `web` (Android passes
        //   `--from-default-profile web`, whose last step fails on iSH with EPERM
        //   while removing an empty staging directory).
        let profiles = "/root/.dsh/profiles"
        var prelude = "find /root/.dsh -maxdepth 6 -type f -name '*.*.lock' -exec rm -f {} + 2>/dev/null; "
        if mode == .safe {
            prelude += "rm -rf \(profiles)/dsh-app-safe \(profiles)/.dsh-app-safe.staging-* 2>/dev/null; "
                + "if [ -d \(profiles)/web ]; then cp -a \(profiles)/web \(profiles)/dsh-app-safe; fi; "
        }
        argv = ["/bin/sh", "-c", prelude + "exec \"$@\"", "dsh"] + argv
        error = nil; token = nil; fatal = false; readyAt = nil
        launchAt = Date()
        setPhase(.starting)
        try kernel.boot(root: value.root)
        // App-owned overlay, written fresh on every start (see storePatch).
        guard GuestFiles.mkdir("/opt/dsh-app", mode: 0o755),
              GuestFiles.write(Self.storePatchPath, Self.storePatch, mode: 0o644) else { throw RuntimeError("E_STORE_PATCH") }
        argv.insert(contentsOf: ["--patch", Self.storePatchPath], at: argv.firstIndex(of: "--host")!)
        if let hook = launchHook {
            // Launcher patches precede app flags, alongside the existing web patch.
            let patches = try hook.prepare(mode == .safe)
            let index = argv.firstIndex(of: "--host")!
            argv.insert(contentsOf: patches.flatMap { ["--patch", $0] }, at: index)
        }
        launchGeneration += 1
        let generation = launchGeneration
        deadline = Date().addingTimeInterval(180)
        enginePID = try kernel.spawn(argv: argv, env: env, output: { [weak self] line, stderr in
            self?.worker.async { self?.onLine(line, stderr: stderr, generation: generation) }
        })
    }
    static func launchEnvironment() -> [String: String] {
        ["HOME": "/root", "DSH_HOME": "/root/.dsh", "TMPDIR": "/tmp",
         "PATH": "/opt/node/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
         "TERM": "xterm-256color", "LANG": "C.UTF-8", "UV_USE_IO_URING": "0",
         "NO_COLOR": "1", "DSH_TELEMETRY_DISABLED": "1",
         // Read on every start so an engine restart picks up travel/timezone changes.
         "TZ": TimeZone.current.identifier]
    }
    private func onLine(_ raw: String, stderr: Bool, generation: Int) {
        guard generation == launchGeneration else { return }
        let line = raw.replacingOccurrences(of: #"\x1b\[[0-9;]*[A-Za-z]"#, with: "", options: .regularExpression)
        if line.hasPrefix("dsh web: ") {
            // Launch URLs never enter logs or events, even in a malformed form.
            if !stderr, phase == .starting,
               let url = URLComponents(string: String(line.dropFirst(9)).trimmingCharacters(in: .whitespaces)),
               url.scheme == "http", url.host == "127.0.0.1", url.port == Int(Self.port),
               let secret = url.queryItems?.first(where: { $0.name == "token" })?.value,
               !secret.isEmpty, secret.count < 4096 { token = secret }
            logs.append("dsh web: [launch token withheld]", stream: "system")
            return
        }
        if line.contains("EADDRINUSE") { error = "EADDRINUSE" }
        if line.contains("Fatal process out of memory") || line.contains("JavaScript heap out of memory") || line.contains("ENOMEM") {
            error = "ENOMEM"
        }
        if line.hasPrefix("dsh: startup failed:") || line.hasPrefix("dsh: fatal ") { fatal = true }
        logs.append(line, stream: stderr ? "stderr" : "stdout")
    }
    private func tick() {
        let batch = logs.drain()
        if !batch.isEmpty {
            deliver(.logs(batch.compactMap { entry in
                guard let seq = entry["seq"] as? Int64, let line = entry["line"] as? String,
                      let stream = entry["stream"] as? String else { return nil }
                return RuntimeLogEntry(seq: seq, line: line, stream: stream)
            }))
        }
        if phase == .starting, token != nil, Self.canConnect() {
            readyAt = Date(); deadline = nil
            logs.append("[dsh-app] dsh web reachable in \(Int(Date().timeIntervalSince(launchAt ?? Date()) * 1000)) ms", stream: "system")
            setPhase(.running)
        }
        if phase == .starting, let deadline, Date() >= deadline {
            try? doStop(); fail("E_START_TIMEOUT")
        }
        if [.starting, .running].contains(phase), let pid = enginePID, let code = kernel.exitStatus(pid) {
            let counted = fatal && (readyAt == nil || Date().timeIntervalSince(readyAt!) < 120)
            if mode != .safe && counted {
                strikes += 1
                if autoSafe && (strikes >= 2 || safeState == "probation") { safeState = "on" }
                prefs.set(strikes, forKey: "runtime.strikes"); prefs.set(safeState, forKey: "runtime.safeState")
            }
            let reason = error ?? "E_ENGINE_EXIT_\(code)"
            try? doStop(); fail(reason)
        }
        if phase == .running, mode == .normal, let readyAt, Date().timeIntervalSince(readyAt) >= 120,
           strikes > 0 || safeState == "probation" {
            strikes = 0; safeState = "off"
            prefs.set(0, forKey: "runtime.strikes"); prefs.set("off", forKey: "runtime.safeState"); setPhase(phase)
        }
    }
    private func doStop() throws {
        token = nil; deadline = nil
        if !kernel.booted { setPhase(installer?.current == true ? .installed : .notInstalled); return }
        setPhase(.stopping)
        // First let DSH shut down, then terminate ALL remaining guest tasks except init.
        if let pid = enginePID {
            kernel.signal(pid, 15)
            let end = Date().addingTimeInterval(3)
            while kernel.processes.contains(where: { $0["pid"]?.int32Value == pid }), Date() < end { Thread.sleep(forTimeInterval: 0.05) }
        }
        for signal: Int32 in [15, 9] {
            let end = Date().addingTimeInterval(signal == 15 ? 2 : 10)
            repeat {
                let tasks = kernel.processes.filter { ($0["pid"]?.intValue ?? 0) > 1 }
                if tasks.isEmpty { break }
                for task in tasks { if let pid = task["pid"] { kernel.signal(pid.int32Value, signal) } }
                Thread.sleep(forTimeInterval: 0.05)
            } while Date() < end
        }
        enginePID = nil; readyAt = nil; launchGeneration += 1
        let remaining = kernel.processes.filter { ($0["pid"]?.intValue ?? 0) > 1 }
        guard remaining.isEmpty else { throw RuntimeError("E_STOP_GUEST_REMAINS") }
        let end = Date().addingTimeInterval(2)
        while !Self.portAvailable() && Date() < end { Thread.sleep(forTimeInterval: 0.05) }
        guard Self.portAvailable() else { throw RuntimeError("E_STOP_PORT_IN_USE") }
        try launchHook?.cleanup()
        logs.append("[dsh-app] stopped: only PID 1 remains; zombies=0; port \(Self.port) released", stream: "system")
        error = nil; setPhase(installer?.current == true ? .installed : .notInstalled)
    }
    private func doReset(groups: [String]) throws {
        let value = try requireInstaller()
        let paths = try RuntimeInstaller.keepPaths(groups)
        if kernel.bootAttempted {
            try value.deferOperation("reset", keep: paths)
            try doStop(); throw RuntimeError("E_RESTART_REQUIRED")
        }
        try value.reset(keep: paths)
        token = nil; error = nil; setPhase(.notInstalled)
    }

    // MARK: Loopback checks

    static let baseURL = URL(string: "http://127.0.0.1:\(port)")!
    public static func portAvailable() -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        if fd < 0 { return false }; defer { close(fd) }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
        var address = loopback()
        return withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
        }
    }
    private static func canConnect() -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        if fd < 0 { return false }; defer { close(fd) }
        var address = loopback()
        // Local loopback connect either succeeds or refuses immediately.
        return withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
        }
    }
    private static func loopback() -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian; address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return address
    }
}
