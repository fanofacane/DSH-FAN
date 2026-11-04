// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import ish

// Serial caller owns lifecycle; the native bridge uses separate guest/output/reaper threads.
final class RuntimeKernel {
    private(set) var bootAttempted = false
    private(set) var booted = false
    func boot(root: URL) throws {
        if booted { return }
        guard !bootAttempted else { throw RuntimeError("E_RESTART_REQUIRED") }
        bootAttempted = true
        if let error = dsh_kernel_boot(root.path) { throw RuntimeError(error) }
        booted = true
    }
    func spawn(argv: [String], env: [String: String], output: @escaping (String, Bool) -> Void) throws -> Int32 {
        // Admission is serialized with stop: it cannot report an empty process
        // table while a launch thread is still about to create a guest child.
        let admitted = DispatchSemaphore(value: 0)
        var pid: Int32 = -1, failure: Int32 = 0
        dsh_kernel_spawn(argv, env, output) { value, error in
            pid = value; failure = error; admitted.signal()
        }
        admitted.wait() // RuntimeController.worker, never the Flutter UI thread.
        if failure < 0 { throw RuntimeError("E_EXEC_\(-failure)") }
        return pid
    }
    func signal(_ pid: Int32, _ signal: Int32) { _ = dsh_kernel_signal(pid, signal) }
    var processes: [[String: NSNumber]] { dsh_kernel_processes() }
    func exitStatus(_ pid: Int32) -> Int? { dsh_kernel_exit_status(pid)?.intValue }
}
