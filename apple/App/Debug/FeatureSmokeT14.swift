// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import DSHClient
import Foundation
import UserNotifications

extension AppSession {
    func smokeT14(_ result: FeatureSmokeContext) async throws {
        let dependencies = result.dependencies
        let notifications = dependencies.notifications
        let previous = notifications.enabled
        let event = "notification-smoke-" + UUID().uuidString
        let identifier = "dsh-task-local-" + event
        let center = UNUserNotificationCenter.current()
        defer {
            notifications.enabled = previous; notifications.setForeground(.active)
            center.removeDeliveredNotifications(withIdentifiers: [identifier]); center.removePendingNotificationRequests(withIdentifiers: [identifier])
        }
        guard await notifications.enable() else { throw DSHError("E_NOTIFICATIONS_DENIED") }
        notifications.setForeground(.inactive)
        let foreground = await notifications.notify(.reply, eventId: event, sessionId: "smoke", hostId: nil)
        guard !foreground else { throw DSHError("E_FOREGROUND_NOTIFICATION") }
        notifications.setForeground(.background)
        guard await notifications.notify(.reply, eventId: event, sessionId: "smoke", hostId: nil) else { throw DSHError("E_NOTIFICATION_ADD") }
        let duplicate = await notifications.notify(.reply, eventId: event, sessionId: "smoke", hostId: nil)
        guard !duplicate else { throw DSHError("E_DUPLICATE_NOTIFICATION") }
        var delivered: [UNNotification] = []
        let deadline = Date().addingTimeInterval(10)
        repeat {
            delivered = await center.deliveredNotifications().filter { $0.request.identifier == identifier }
            if !delivered.isEmpty { break }; try await Task.sleep(nanoseconds: 200_000_000)
        } while Date() < deadline
        guard let alert = delivered.first, alert.request.content.body == String(localized: "Open DSH to read the reply.") else { throw DSHError("E_NOTIFICATION_DELIVERY") }
        result.set("systemDelivery", true); result.set("foregroundSuppressed", true)
        result.set("duplicateSuppressed", true); result.set("genericBody", true)
        result.set("simulatedBackgroundGate", true)
    }
}
#endif
