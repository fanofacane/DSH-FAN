// SPDX-License-Identifier: AGPL-3.0-or-later
// Port of cases from DSH Go packages/dsh_client/test/trace_test.dart and
// app/test/chat/{run_info,turn_summary}_test.dart, using synthetic durable frames.
import Foundation
import Testing
@testable import DSHClient

struct TurnTraceTests {
    @Test func modelApprovalToolAndReply() throws {
        var fold = TurnTraceFold()
        record(&fold, 1, 1000, "turn/start", ["turn": 1])
        record(&fold, 2, 1061, "step/start", ["step": 1])
        record(&fold, 3, 1200, "assistant/attempt", ["step": 1, "stream": [
            ["type": "chunk", "time": 1150, "chunk": ["type": "reasoning-delta"]]
        ]])
        record(&fold, 4, 1210, "llm/retry", ["step": 1, "failure": ["code": "RATE_LIMIT"]])
        #expect(fold.running?.current?.model?.retries == ["RATE_LIMIT"])
        message(&fold, 5, 2599, step: 1, input: 3775, output: 209, hit: 6400, first: 1500, calls: 1)
        record(&fold, 6, 2600, "tool/call", ["callId": "bash", "step": 1, "name": "bash", "arguments": #"{"command":"echo hi"}"#])
        record(&fold, 7, 2601, "approval/asked", ["id": "ask", "callId": "bash", "toolName": "bash"])
        #expect(fold.running?.current?.kind == .approval)
        #expect(fold.running?.current?.end == nil)
        #expect(fold.running?.spans.contains { $0.kind == .tool } == false)
        record(&fold, 8, 2605, "approval/decided", ["id": "ask", "outcome": "allowed-once"])
        #expect(fold.running?.current?.kind == .tool)
        #expect(fold.running?.current?.start == date(2605))
        record(&fold, 9, 2691, "tool/result", ["callId": "bash", "message": ["isError": false]])
        #expect(fold.running?.current?.kind == .model)
        record(&fold, 10, 2704, "step/start", ["step": 2])
        message(&fold, 11, 3078, step: 2, input: 158, output: 2, hit: 10240, first: 2800)
        record(&fold, 12, 3081, "turn/end", ["turn": 1, "reason": ["kind": "completed"]])

        let turn = try #require(fold.completed.first)
        #expect(turn.endReason == "completed" && turn.steps == 2 && !turn.running)
        #expect(ms(turn.duration) == 2081)
        #expect(turn.spans.map(\.kind) == [.model, .approval, .tool, .model])
        #expect(turn.spans.allSatisfy { !$0.open })
        #expect(ms(turn.spans[0].duration) == 1538)
        #expect(ms(turn.ttft) == 89)
        #expect(ms(turn.spans[0].decoding) == 1449)
        #expect(turn.spans[0].model?.toolCalls == 1)
        #expect(turn.spans[1].outcome == .allowedOnce)
        #expect(turn.spans[2].dispatched == date(2600) && turn.spans[2].start == date(2605))
        #expect(ms(turn.waitTime) == 4 && ms(turn.toolTime) == 86 && ms(turn.modelTime) == 1912)
        #expect(turn.usage.uncachedInput == 3933 && turn.usage.cacheRead == 16640 && turn.usage.output == 211)
        #expect(turn.usage.total == 20784 && turn.usage.requests == 2)
        #expect(abs((turn.usage.cacheHitRate ?? 0) - 16640.0 / 20573) < 1e-9)
        #expect(abs((RunPricing.estimate(turn) ?? 0) - 0.0102196) < 1e-9)
    }

    @Test func partialHistoryAndInterruptedTurn() throws {
        var fold = TurnTraceFold()
        record(&fold, 0, 100, "tool/call", ["callId": "incomplete", "name": "bash"])
        record(&fold, 1, 200, "turn/end", ["turn": 1])
        #expect(fold.turns.isEmpty)
        record(&fold, 2, 1000, "turn/start", ["turn": 2])
        record(&fold, 3, 2000, "tool/call", ["callId": "ask", "name": "ask_user_question"])
        record(&fold, 4, 2600, "agent/status")
        record(&fold, 5, 9000, "turn/start", ["turn": 3])
        record(&fold, 5, 9000, "turn/start", ["turn": 3]) // Replayed event.
        let closed = try #require(fold.completed.first)
        #expect(fold.completed.count == 1)
        #expect(closed.endSeq == nil && closed.end == date(2600) && closed.endReason == "interrupted")
        #expect(closed.spans.first?.kind == .question && closed.spans.first?.cutShort == true)
        #expect(closed.usage.total == nil && closed.usage.cacheHitRate == nil)
        #expect(fold.running?.startSeq == 5 && fold.running?.current?.end == nil)
        record(&fold, 6, 9010, "compaction/start")
        #expect(fold.compactionStart == date(9010))
        record(&fold, 7, 9500, "compaction/end")
        #expect(fold.compactionStart == nil)
    }

    @Test func missingTimestampsAndIncompleteUsage() throws {
        #expect(RunFact(["type": "turn/start", "seq": 0]) == nil)
        var fold = TurnTraceFold()
        record(&fold, 1, 1000, "turn/start")
        record(&fold, 2, 1200, "assistant/message", ["step": 1, "interrupted": true,
            "message": ["content": [["type": "text", "text": "prefix"]]]])
        record(&fold, 3, 1210, "turn/end", ["reason": ["kind": "aborted"]])
        let trace = try #require(fold.completed.first)
        #expect(trace.steps == 1 && trace.endReason == "aborted")
        #expect(trace.spans.first?.model?.interrupted == true)
        #expect(trace.usage.total == nil && trace.ttft == nil && RunPricing.estimate(trace) == nil)
        #expect(TraceUsage(["inputTokens": Int.max, "cacheReadTokens": 1])?.input == nil)
        #expect(TraceUsage(["outputTokens": 2])?.total == nil)
    }

    @Test func groupCountsAndNumberedEdits() throws {
        var fold = TurnTraceFold()
        record(&fold, 1, 1000, "turn/start")
        tool(&fold, 2, "bash", #"{"command":"ls"}"#, result: "no sandbox backend is usable", failed: true)
        tool(&fold, 4, "bash", #"{"command":"ls"}"#)
        tool(&fold, 6, "read", #"{"file_path":"./a.txt"}"#, meta: ["lines": [
            ["number": 9, "text": "first"], ["number": 10, "text": "old"], ["number": 11, "text": "last"]
        ]])
        tool(&fold, 8, "read", #"{"file_path":"/root/workspace/a.txt"}"#, result: "9: first\n10: old\n11: last")
        tool(&fold, 10, "edit", #"{"file_path":"a.txt","old_string":"old","new_string":"new\nextra"}"#)
        tool(&fold, 12, "edit", #"{"file_path":"a.txt","old_string":"last","new_string":"end"}"#)
        tool(&fold, 14, "write", #"{"file_path":"new.txt","content":"hello\nworld\n"}"#, meta: ["operation": "create"])
        tool(&fold, 16, "write", #"{"file_path":"ignored.txt","content":"x"}"#, failed: true)
        record(&fold, 18, 1180, "tool/call", ["callId": "pending", "name": "grep", "arguments": #"{"pattern":"test"}"#])
        #expect(fold.running?.changes.isEmpty == true)
        record(&fold, 19, 1190, "turn/end", ["reason": ["kind": "aborted"]])
        let trace = try #require(fold.completed.first)
        let summary = ToolSummary(trace.spans)
        #expect(summary.commands == 1 && summary.readFiles == 1 && summary.editedFiles == 2)
        #expect(summary.failed == 1 && summary.total == 6 && summary.searches == 0)
        #expect(trace.changes.map(\.shownPath) == ["a.txt", "new.txt"])
        let edit = try #require(trace.changes.first)
        #expect(edit.edits == 2 && edit.added == 3 && edit.removed == 2)
        #expect(edit.hunks.map(\.oldStart) == [10, 12] && edit.hunks.map(\.newStart) == [10, 12])
        #expect(trace.changes.last?.patch.hasPrefix("--- /dev/null\n+++ b/new.txt\n@@ -0,0 +1,2 @@\n") == true)
    }

    @Test func wholeFileWriteAndAmbiguousRead() throws {
        var fold = TurnTraceFold()
        record(&fold, 1, 1000, "turn/start")
        tool(&fold, 2, "str_replace_editor", #"{"command":"view","path":"x"}"#, result: "1: same\n2: same")
        tool(&fold, 4, "str_replace_editor", #"{"command":"str_replace","path":"x","old_str":"same","new_str":"different"}"#)
        tool(&fold, 6, "write", #"{"file_path":"y","content":"hello\nworld\n"}"#, meta: [
            "operation": "update", "diffs": [["oldText": "earth", "newText": "world"]]
        ])
        record(&fold, 8, 1080, "turn/end")
        let changes = try #require(fold.completed.first).changes
        #expect(changes.count == 2)
        #expect(changes.first?.hunks.first?.newStart == nil)
        #expect(changes.last?.hunks.first?.oldStart == 2 && changes.last?.hunks.first?.newStart == 2)
    }

    @Test func unknownPriceAndFormatting() throws {
        var fold = TurnTraceFold()
        record(&fold, 1, 1000, "turn/start")
        message(&fold, 2, 2000, step: 1, input: 100, output: 2, hit: 0, first: 1200, provider: "custom")
        record(&fold, 3, 2010, "turn/end")
        #expect(RunPricing.estimate(try #require(fold.completed.first)) == nil)
        #expect(RunFormat.clock(7) == "0:07")
        #expect(RunFormat.clock(765) == "12:45")
        #expect(RunFormat.clock(3725) == "1:02:05")
        #expect(RunFormat.clock(-3) == "0:00")
        #expect(RunFormat.tokens(80_084) == "80.1K")
        #expect(RunFormat.tokens(999_900) == "1M")
        #expect(RunFormat.tokens(1_050_000) == "1.05M")
        #expect(RunFormat.percent(0.004) == "<1%")
        #expect(RunFormat.duration(0.04) == String(localized: "<0.1 s"))
        #expect(RunFormat.duration(0.95) == String(localized: "\("0.9") s"))
        #expect(RunFormat.cost(0.004) == String(localized: "Under ¥0.01"))
    }

    @Test func estimateRequiresCompleteKnownSessionUsage() throws {
        var fold = TurnTraceFold()
        record(&fold, 1, 1000, "turn/start")
        message(&fold, 2, 2000, step: 1, input: 100, output: 2, hit: 50, first: 1200)
        record(&fold, 3, 2010, "turn/end")
        let metrics = SessionMetrics(["tokenUsage": ["uncachedInputTokens": 100, "cacheReadTokens": 50, "outputTokens": 2],
                                      "sessionStats": ["turns": 1]])
        #expect(metrics.total == 152)
        #expect(RunPricing.sessionEstimate(fold.turns, metrics: metrics) != nil)
        #expect(RunPricing.sessionEstimate(fold.turns, metrics: SessionMetrics([:])) == nil)
        record(&fold, 4, 3000, "turn/start")
        message(&fold, 5, 4000, step: 1, input: 100, output: 2, hit: 50, first: 3200, provider: "custom")
        #expect(RunPricing.sessionEstimate(fold.turns, metrics: metrics) == nil)
    }

    private func record(_ fold: inout TurnTraceFold, _ seq: Int, _ time: Double, _ type: String, _ data: [String: Any] = [:]) {
        let frames = DSHClient.decode(["type": "event", "event": ["seq": seq, "time": time, "type": type, "data": data]])
        for case .timeline(let facts, _) in frames {
            for fact in facts { fold.apply(fact) }
        }
    }

    private func message(_ fold: inout TurnTraceFold, _ seq: Int, _ time: Double, step: Int, input: Int, output: Int,
                         hit: Int, first: Int, calls: Int = 0, provider: String = "deepseek-official") {
        let content = [["type": "text", "text": "ok"]] + Array(repeating: ["type": "tool-call"], count: calls)
        record(&fold, seq, time, "assistant/message", ["step": step, "message": [
            "content": content, "source": ["provider": provider, "model": "deepseek-flash"]
        ], "usage": ["inputTokens": input, "outputTokens": output, "cacheReadTokens": hit],
           "stream": [["type": "text-chunks", "time0": Double(first), "dt": [100]]]])
    }

    private func tool(_ fold: inout TurnTraceFold, _ seq: Int, _ name: String, _ arguments: String,
                      result: String = "", meta: [String: Any] = [:], failed: Bool = false) {
        let id = "c\(seq)"
        record(&fold, seq, Double(1000 + seq * 10), "tool/call", ["callId": id, "name": name, "arguments": arguments])
        record(&fold, seq + 1, Double(1010 + seq * 10), "tool/result", [
            "callId": id, "meta": meta, "message": ["isError": failed, "content": [["type": "text", "text": result]]]
        ])
    }

    private func date(_ ms: Int) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }
    private func ms(_ seconds: TimeInterval?) -> Int? { seconds.map { Int(($0 * 1000).rounded()) } }
}
