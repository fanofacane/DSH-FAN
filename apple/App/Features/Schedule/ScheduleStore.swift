// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import Foundation
import Observation

@MainActor @Observable final class ScheduleStore {
    private(set) var entries: [ScheduleEntry] = []
    private let context: SessionContext
    private func api() throws -> ScheduleAPI { ScheduleAPI(client: try context.requireClient()) }
    init(context: SessionContext) { self.context = context }
    func reset() { entries = [] }
    func schedules() async throws -> [ScheduleEntry] { entries = try await api().catalog(); return entries }
    @discardableResult func updateSchedule(_ task: ScheduleEntry, title: String, prompt: String, timing: ScheduleChange? = nil) async throws -> ScheduleEntry {
        let updated = try await api().update(task, title: title, prompt: prompt, change: timing)
        if let index = entries.firstIndex(where: { $0.id == task.id }) { entries[index] = updated }
        return updated
    }
    func deleteSchedule(_ task: ScheduleEntry) async throws { _ = try await api().delete(task) }
}
