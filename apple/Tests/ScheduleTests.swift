// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing
@testable import DSHClient
struct ScheduleTests {
    @Test func contracts() {
        let task = ScheduleEntry(["id": "task-1", "sessionId": "s", "title": "Task", "prompt": "do it", "kind": "daily", "status": "active", "lastDelivery": ["deliveredAt": "2026-11-03T12:00:00Z"], "scheduledAt": "2026-11-04T01:00:00.000Z"])!
        #expect(task.expected["sessionId"] == nil && task.expected["status"] == nil && task.expected["lastDelivery"] == nil)
        #expect(task.expected["id"] as? String == "task-1" && task.active)
        #expect(ScheduleEntry.date(task.expected["scheduledAt"]) != nil)
        #expect(ScheduleEntry.date("2026-11-03T12:00:00Z") != nil)
        #expect(ScheduleEntry(["id": "task-1"]) == nil)
    }
}
