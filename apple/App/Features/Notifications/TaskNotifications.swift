// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import Observation
import SwiftUI
import UIKit
import UserNotifications

@MainActor @Observable final class TaskNotifications: NSObject, UNUserNotificationCenterDelegate {
    enum Kind: String { case reply, failed, approval, question, finished }
    private var muted: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "notifications.muted") ?? []) {
        didSet { UserDefaults.standard.set(muted.sorted(), forKey: "notifications.muted") }
    }

    func includes(_ kind: Kind) -> Bool { !muted.contains(kind.rawValue) }
    func setIncluded(_ value: Bool, for kind: Kind) {
        if value { muted.remove(kind.rawValue) } else { muted.insert(kind.rawValue) }
        if kind == .reply { // Both current replies and background turns are completion alerts.
            if value { muted.remove(Kind.finished.rawValue) } else { muted.insert(Kind.finished.rawValue) }
        }
    }
    var enabled = UserDefaults.standard.bool(forKey: "notifications.tasks") {
        didSet { UserDefaults.standard.set(enabled, forKey: "notifications.tasks") }
    }
    private(set) var authorization = UNAuthorizationStatus.notDetermined
    private(set) var foreground = true
    private(set) var error: String?
    var onOpen: ((String, String?) -> Void)?
    private var seen: Set<String> = []
    private var grace = UIBackgroundTaskIdentifier.invalid
    private let center: UNUserNotificationCenter
    private let application: UIApplication
    init(center: UNUserNotificationCenter, application: UIApplication) {
        self.center = center
        self.application = application
        super.init(); center.delegate = self
    }
    func refresh() async { authorization = await center.notificationSettings().authorizationStatus }
    @discardableResult func enable() async -> Bool {
        do {
            enabled = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refresh(); error = enabled ? nil : "E_NOTIFICATIONS_DENIED"
        } catch { enabled = false; self.error = "E_NOTIFICATION_" + String((error as NSError).code) }
        return enabled
    }
    func setForeground(_ phase: ScenePhase, allowGrace: Bool = false) {
        foreground = phase != .background
        if foreground { finishGrace() }
        else if allowGrace && grace == .invalid {
            grace = application.beginBackgroundTask(withName: "Finish DSH turn") { [weak self] in
                Task { @MainActor in self?.finishGrace() }
            }
        }
    }
    func finishGrace() {
        guard grace != .invalid else { return }
        let task = grace; grace = .invalid; application.endBackgroundTask(task)
    }
    @discardableResult func notify(_ kind: Kind, eventId: String, sessionId: String, hostId: String?) async -> Bool {
        let id = "dsh-task-" + (hostId ?? "local") + "-" + eventId
        guard enabled, includes(kind), !foreground, !seen.contains(id) else { return false }
        await refresh()
        guard [.authorized, .provisional, .ephemeral].contains(authorization) else { error = "E_NOTIFICATIONS_DENIED"; return false }
        guard enabled, includes(kind), !foreground, seen.insert(id).inserted else { return false }
        let content = UNMutableNotificationContent()
        switch kind {
        case .reply: content.title = String(localized: "DSH finished a reply"); content.body = String(localized: "Open DSH to read the reply.")
        case .failed: content.title = String(localized: "A DSH task stopped"); content.body = String(localized: "Open DSH to check its result.")
        case .approval, .question: content.title = String(localized: "DSH is waiting for you"); content.body = String(localized: "Open DSH to respond.")
        case .finished: content.title = String(localized: "DSH task finished"); content.body = String(localized: "Open DSH to check its result.")
        }
        content.sound = .default
        content.userInfo = ["dshSession": sessionId]
        if let hostId { content.userInfo["dshHost"] = hostId }
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
            error = nil; return true
        } catch { seen.remove(id); self.error = "E_NOTIFICATION_" + String((error as NSError).code); return false }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await MainActor.run { foreground ? [] : [.banner, .sound] }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let session = info["dshSession"] as? String else { return }
        let host = info["dshHost"] as? String
        await MainActor.run { onOpen?(session, host) }
    }
}
