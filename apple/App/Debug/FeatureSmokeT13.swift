// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import DSHClient
import Foundation

extension AppSession {
    func smokeT13(_ result: FeatureSmokeContext) async throws {
        self.transcript.newChat()
        let title = "iOS schedule smoke " + UUID().uuidString.lowercased().prefix(8)
        await self.transcript.send("请使用 schedule_create 工具创建一个一次性任务：4 小时后执行，标题严格为「\(title)」，任务指令为「只回复 schedule-smoke」。不要创建其他任务，完成后只回复已创建。")
        try await smokeWait(seconds: 120) { !self.transcript.busy && self.transcript.items.contains { $0.role == .assistant && $0.state == .done } }
        guard let parent = self.transcript.currentSessionId else { throw DSHError("E_NO_SESSION") }
        do {
            let owned = try await self.schedule.schedules().filter { $0.sessionId == parent }
            guard owned.count == 1, let task = owned.first else { throw DSHError("E_SCHEDULE_CREATE") }
            let history = try await self.connection.scheduleAPI.history(sessionId: parent, id: task.taskId, limit: 20)
            guard history.records != nil else { throw DSHError("E_SCHEDULE_HISTORY") }
            let updated = try await self.schedule.updateSchedule(task, title: String(title) + " edited", prompt: "Only reply schedule-smoke.", timing: .every(seconds: 3600))
            guard updated.title == String(title) + " edited", updated.kind == "every" else { throw DSHError("E_SCHEDULE_EDIT") }
            try await self.schedule.deleteSchedule(updated)
            let remaining = try await self.schedule.schedules()
            guard !remaining.contains(where: { $0.id == task.id }) else { throw DSHError("E_SCHEDULE_DELETE") }
        } catch {
            if let owned = try? await self.schedule.schedules().filter({ $0.sessionId == parent }) {
                for task in owned { try? await self.schedule.deleteSchedule(task) }
            }
            throw error
        }
        result.set("catalogHistoryUpdateDelete", true); result.set("realModelCreatedTask", true); result.set("fixtureRemoved", true)
    }
}
#endif
