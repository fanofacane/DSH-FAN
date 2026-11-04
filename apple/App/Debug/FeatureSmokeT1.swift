// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import DSHClient
import Foundation

extension AppSession {
    func smokeT1(_ result: FeatureSmokeContext) async throws {
        guard self.transcript.canSend else { throw DSHError(self.connection.keyConfigured ? "E_CANNOT_SEND" : "E_NEEDS_USER_KEY") }
        self.transcript.newChat()
        await self.transcript.send("请使用 todo 工具记录三条待办：检查目录、计算 2+2、汇报结果。逐一执行，每步完成后更新 todo 状态。不要创建长期目标。")
        var sawTodos = false, sawProgress = false
        let end = Date().addingTimeInterval(240)
        while Date() < end {
            let todos = self.control.projection.todos
            sawTodos = sawTodos || !todos.isEmpty
            sawProgress = sawProgress || todos.contains { $0.status == "completed" }
            if !self.transcript.busy && sawTodos { break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        result.set("realModel", true); result.set("todosObserved", sawTodos); result.set("progressObserved", sawProgress)
        guard sawTodos, sawProgress, let id = self.transcript.currentSessionId else { throw DSHError("E_TODO_NOT_OBSERVED") }
        try await self.connection.controlAPI.createGoal(agentId: id, objective: "只回复完成", maxGoalRounds: 1)
        try await smokeWait { self.control.projection.goal != nil }
        guard let initial = self.control.projection.goal else { throw DSHError("E_GOAL_NOT_OBSERVED") }
        try await self.control.changeGoal(.pause, goal: initial)
        try await smokeWait { self.control.projection.goal?.phase == "paused" }
        result.set("pause", true)
        do { try await self.control.changeGoal(.pause, goal: initial); throw DSHError("E_STALE_REF_ACCEPTED") }
        catch let error as DSHError {
            guard error.code != "E_STALE_REF_ACCEPTED" else { throw error }
            result.set("staleRevisionRejected", true); result.set("staleRevisionCode", error.code)
        }
        if let paused = self.control.projection.goal { try await self.control.changeGoal(.edit, goal: paused, objective: "只回复已完成") }
        try await smokeWait { self.control.projection.goal?.objective == "只回复已完成" }
        if let edited = self.control.projection.goal { try await self.control.changeGoal(.resume, goal: edited) }
        try await smokeWait { self.control.projection.goal?.phase != "paused" }
        result.set("resume", true)
        if let goal = self.control.projection.goal, goal.phase != "complete" { try await self.control.changeGoal(.complete, goal: goal) }
        try await smokeWait { self.control.projection.goal?.phase == "complete" }
        if let goal = self.control.projection.goal { try await self.control.changeGoal(.clear, goal: goal) }
        try await smokeWait { self.control.projection.goal == nil }
        result.set("clear", true)
    }
}
#endif
