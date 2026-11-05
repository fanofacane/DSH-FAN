// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/test/chat/{activity_strip_golden_test,dock/dock_golden_test}.dart.
#if DEBUG
import DSHClient
import SwiftUI

enum DebugDockFixtures {
    static let now = Date(timeIntervalSince1970: 1_792_720_959.950)
    static let running: [TodoItem] = [
        TodoItem(content: "找到重复提交的原因", status: "completed"),
        TodoItem(content: "给提交加锁", status: "completed"),
        TodoItem(content: "补一个连点测试", status: "completed"),
        TodoItem(content: "跑测试", status: "in_progress"),
        TodoItem(content: "更新 README 的运行说明", status: "pending"),
        TodoItem(content: "整理改动说明", status: "pending"),
        TodoItem(content: "提交前再看一遍", status: "pending")
    ]
    static let done = Array(running.prefix(3))
    static func goalValue(phase: String = "active") -> JSONValue {
        ["goal": ["id": "debug-goal", "revision": 1, "objective": "把登录迁到新接口\n并补齐连点测试，旧接口保留到下个版本",
                  "phase": .string(phase), "maxGoalRounds": 12],
         "roundsStarted": phase == "blocked" ? 12 : 3,
         "blockedReason": phase == "blocked" ? ["message": "轮次用完了，提高上限后再继续"] : nil]
    }
    static func goal(phase: String = "active") -> GoalState? { GoalState(goalValue(phase: phase).foundation) }
}

struct DebugActivityGallery: View {
    var levels = false
    private let now = Date(timeIntervalSince1970: 1_792_460_400)

    var body: some View {
        VStack(spacing: 10) {
            if levels {
                ForEach(1...4, id: \.self) { level in
                    ActivityStrip(activity: item(.thinking, "思考中"), previewLevel: level)
                }
                HStack {
                    ForEach(1...4, id: \.self) { level in
                        ActivityWhale(activity: item(.thinking, "思考中"), rate: RunTokenRate(), previewLevel: level, height: 56)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, Space.sm)
            } else {
                ActivityStrip(activity: item(.waiting, "思考中", elapsed: 1))
                ActivityStrip(activity: item(.thinking, "思考中"), previewLevel: 2)
                ActivityStrip(activity: failedTool, previewLevel: 3)
                ActivityStrip(activity: item(.writing, "写回复中", narration: "修复登录按钮的重复提交"), previewLevel: 4)
                ActivityStrip(activity: item(.tool, "跑", "flutter test test/auth", code: true), progress: (3, 5))
                ActivityStrip(activity: item(.tool, "改", "lib/auth/login_controller.dart", code: true), previewLevel: 3)
                ActivityStrip(activity: item(.approval, "等你确认", "跑 flutter test test/auth"))
                ActivityStrip(activity: item(.question, "等你回答", "数据库用哪一个?"))
                ActivityStrip(activity: item(.retry, "重试中", "第 2 次", rateLimited: true))
                ActivityStrip(activity: item(.compaction, "压缩上下文"))
            }
        }
        .padding(.horizontal, Space.floatInset)
        .padding(.top, Space.xxl)
        .frame(maxHeight: .infinity, alignment: .top)
        .background { AppBackdrop() }
        .environment(\.runClockOverride, now)
    }

    private var failedTool: RunActivity {
        var activity = item(.thinking, "思考中", elapsed: 1)
        activity.narration = "测试红了，看看哪里没对上"
        return activity
    }

    private func item(_ kind: RunActivity.Kind, _ title: String, _ detail: String = "", code: Bool = false,
                      elapsed: Double = 9, narration: String? = nil, rateLimited: Bool = false) -> RunActivity {
        RunActivity(kind: kind, title: title, detail: detail, code: code,
                    since: now.addingTimeInterval(-elapsed), turnStart: now.addingTimeInterval(-47),
                    narration: narration, rateLimited: rateLimited)
    }
}

struct DebugDockGallery: View {
    var body: some View {
        VStack(spacing: Space.md) {
            TodoDockBar(todos: DebugDockFixtures.running, running: true)
            TodoDockBar(todos: DebugDockFixtures.done, running: true)
            TodoDockBar(todos: DebugDockFixtures.running, running: false)
            TodoDockBar(todos: DebugDockFixtures.running, running: true, initiallyOpen: true)
            ForEach(["active", "paused", "complete", "blocked"], id: \.self) { phase in
                if let goal = DebugDockFixtures.goal(phase: phase) { GoalDockBar(goal: goal) {} }
            }
            if let goal = DebugDockFixtures.goal() { GoalDockBar(goal: goal, busy: true) {} }
        }
        .padding(.horizontal, Space.floatInset)
        .padding(.top, Space.xxl)
        .frame(maxHeight: .infinity, alignment: .top)
        .background { AppBackdrop() }
    }
}
#endif
