// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import Observation
import SwiftUI
import UIKit
import UserNotifications

@MainActor @Observable final class TaskNotifications: NSObject, UNUserNotificationCenterDelegate {
    enum Kind { case reply, attention, finished }
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
        guard enabled, !foreground, !seen.contains(id) else { return false }
        await refresh()
        guard [.authorized, .provisional, .ephemeral].contains(authorization) else { error = "E_NOTIFICATIONS_DENIED"; return false }
        guard enabled, !foreground, seen.insert(id).inserted else { return false }
        let content = UNMutableNotificationContent()
        switch kind {
        case .reply: content.title = String(localized: "DSH finished a reply"); content.body = String(localized: "Open DSH to read the reply.")
        case .attention: content.title = String(localized: "DSH is waiting for you"); content.body = String(localized: "Open DSH to respond.")
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

struct TaskNotificationSettingsPage: View {
    @Environment(TaskNotifications.self) private var notifications
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        SettingsPage(title: "Notifications and background") {
            SettingsGroup {
                SettingsToggleRow(title: "Task notifications", isOn: Binding(get: { notifications.enabled }, set: { value in
                    if value { Task { await notifications.enable() } } else { notifications.enabled = false }
                }))
                SettingsRow(title: "System permission", subtitle: permissionLabel) { EmptyView() }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: { SettingsRow(title: "Open iOS Settings") }.buttonStyle(.plain)
            }
            if let code = notifications.error { Text("Request failed: \(code)").type(.bodySmall).foregroundStyle(DS.danger).padding(.bottom, 16) }
            SettingsGroup(header: "iOS background limits") {
                Text("iOS may suspend DSH within seconds of leaving the app. A running turn can request a short extension, often around 30 seconds; the system decides the actual time.")
                    .type(.bodyMedium).foregroundStyle(DS.ink).padding(16)
                Text("Local tasks and schedules need this app’s engine to keep running. Keep DSH open for reliable local work.")
                    .type(.bodyMedium).foregroundStyle(DS.ink).padding(16)
                Text("A remote host can keep working, but a suspended iOS app cannot receive new events or issue completion alerts. DSH does not provide server push notifications.")
                    .type(.bodyMedium).foregroundStyle(DS.ink).padding(16)
                Text("Alerts contain no message text, tool arguments or credentials.")
                    .type(.bodySmall).foregroundStyle(DS.inkFaint).padding(16)
            }
        }
        .task { await notifications.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await notifications.refresh() } } }
    }
    private var permissionLabel: String {
        switch notifications.authorization {
        case .authorized, .provisional, .ephemeral: String(localized: "Allowed")
        case .denied: String(localized: "Denied")
        default: String(localized: "Not requested")
        }
    }
}
