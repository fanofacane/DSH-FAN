// SPDX-License-Identifier: AGPL-3.0-or-later
// Exercises the native trace and usage projections with one real model turn.
#if DEBUG
import DSHClient
import Foundation

extension AppSession {
    nonisolated static var captureRunInfo: Bool {
        ProcessInfo.processInfo.arguments.contains("-dsh-run-info-capture")
    }

    func smokeT12(_ result: FeatureSmokeContext) async throws {
        guard transcript.canSend else { throw DSHError(connection.keyConfigured ? "E_CANNOT_SEND" : "E_NEEDS_USER_KEY") }
        transcript.newChat()
        let path = "/tmp/dsh-fan-run-info-" + UUID().uuidString.prefix(8).lowercased() + ".txt"
        await transcript.send("""
        请依次实际执行这些工具调用，验证 DSH Fan 的运行轨迹。使用 todo_write 建三项：准备验证、等待计时、写验证文件。
        将第一项标为完成、第二项标为进行中后，调用 bash 运行 sleep 8。只运行该命令。
        再用 write 或 str_replace_editor 的 create 在 \(path) 新建一个文本文件，写两行 “DSH Fan” 和 “trace ready”。
        用 read 读取该文件，最后将待办全部标为完成，并简短报告结果。无需联网或安装任何东西。
        """)
        result.set("realModel", true)
        if Self.captureRunInfo {
            try await smokeWait(seconds: 105) {
                !self.control.projection.todos.isEmpty &&
                    self.transcript.traceFold.running?.spans.contains { $0.kind == .tool && $0.toolName == "bash" && $0.open } == true
            }
            try await capture("running", result: result)
        }
        try await smokeWait(seconds: 180) { !self.transcript.busy && self.transcript.traceFold.completed.last != nil }
        guard let trace = transcript.traceFold.completed.last,
              trace.endReason == "completed", let end = trace.end,
              let total = trace.usage.total, total > 0, trace.steps > 0,
              trace.spans.allSatisfy({ span in
                  guard let finish = span.end else { return false }
                  return span.start >= trace.start && finish >= span.start && finish <= end
              }), trace.spans.contains(where: { $0.kind == .tool && $0.result != nil })
        else { throw DSHError("E_T12_TRACE") }
        result.set("closedSpans", trace.spans.count)
        result.set("modelSteps", trace.steps)
        result.set("firstTokenReported", trace.ttft != nil)
        guard trace.changes.contains(where: { $0.path == path && $0.created && $0.added > 0 }) else {
            throw DSHError("E_T12_FILE_CHANGE")
        }
        result.set("fileChanges", trace.changes.count)
        try await smokeWait(seconds: 30) {
            let metrics = self.control.projection.metrics
            return metrics.turns == 1 && metrics.total == total && metrics.fraction != nil
        }
        let usage = control.projection.metrics
        guard usage.input == trace.usage.input, usage.output == trace.usage.output else { throw DSHError("E_T12_USAGE") }
        guard let used = usage.pressureTokens, let window = usage.contextWindow, window > 0,
              usage.fraction == min(1, Double(used) / Double(window)) else { throw DSHError("E_T12_CONTEXT") }
        result.set("footnoteTokens", total)
        result.set("projectionTokens", usage.total)
        result.set("sessionStatsTurns", usage.turns)
        result.set("contextFraction", usage.fraction)
        result.set("contextPressureMatched", true)
        if Self.captureRunInfo {
            try await capture("finished", result: result)
            runCapturePanel = .usage
            try await capture("usage", result: result, settling: true)
            runCapturePanel = nil
            try await Task.sleep(for: .milliseconds(650))
            runCapturePanel = .trajectory(TraceReference(session: transcript.currentSessionId, startSeq: trace.startSeq))
            try await capture("trajectory", result: result, settling: true)
        }
    }

    private func capture(_ phase: String, result: FeatureSmokeContext, settling: Bool = false) async throws {
        if settling { try await Task.sleep(for: .milliseconds(850)) }
        result.set("capture", phase)
        result.save()
        try await Task.sleep(for: .seconds(3))
    }
}
#endif
