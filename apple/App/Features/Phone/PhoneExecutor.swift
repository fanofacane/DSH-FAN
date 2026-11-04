// SPDX-License-Identifier: AGPL-3.0-or-later
// System actions for phone control. Ported from 原 Flutter 版 ios/Runner/Phone/PhonePlugin.swift
// without Flutter; tool definitions, confirmation and task scope live in PhoneController.
// Result texts are for the model (agent tool results), not App UI strings.
import AlarmKit
import DSHClient
import EventKit
import MessageUI
import SwiftUI
import UIKit
import UserNotifications

struct PhoneActionResult {
    var ok: Bool
    var text: String
    /// A pending app jump, committed after the MCP reply is flushed.
    var deferred: String?
}

/// The iOS 26 SDK class cannot be stored directly in a type deployed to iOS 17.
/// Erasure stays inside this availability boundary; callers receive the concrete SDK type.
struct PhoneAlarms {
    private let storage: AnyObject?
    private init(storage: AnyObject?) { self.storage = storage }
    static let unavailable = PhoneAlarms(storage: nil)
    @available(iOS 26, *) init(_ manager: AlarmManager) { storage = manager }
    @available(iOS 26, *) var manager: AlarmManager? { storage as? AlarmManager }
}

@MainActor
final class PhoneExecutor: NSObject, MFMessageComposeViewControllerDelegate {
    static let callbackScheme = "dshapp"
    private let store = EKEventStore()
    private let center = UNUserNotificationCenter.current()
    private(set) var operation = 0
    var enabled = false
    var stopTitle = "Stop"
    var shortcuts = Set<String>()
    private var leases = Set<UIBackgroundTaskIdentifier>()
    private var jumps: [String: (URL, UIBackgroundTaskIdentifier, Date)] = [:]
    private var callback: (nonce: String, name: String, until: Date)?
    private var shortcutResult = ""

    private let application: UIApplication
    private let alarms: PhoneAlarms

    init(application: UIApplication, alarms: PhoneAlarms) {
        self.application = application
        self.alarms = alarms
        super.init()
    }

    private var foreground: Bool { application.applicationState == .active }
    private func reply(_ text: String, ok: Bool = true, deferred: String? = nil) -> PhoneActionResult {
        PhoneActionResult(ok: ok, text: text, deferred: deferred)
    }
    private func text(_ args: [String: JSONValue], _ name: String, limit: Int = 16384) -> String? {
        guard let value = args[name]?.string, !value.isEmpty, value.count <= limit, !value.contains("\0") else { return nil }
        return value
    }

    func configure(enabled: Bool, shortcuts: Set<String>, stopTitle: String) {
        operation += 1
        self.enabled = enabled; self.shortcuts = shortcuts; self.stopTitle = stopTitle
        if !enabled { cancelDeferred(); shortcutResult = "" }
    }

    func cancelDeferred() {
        operation += 1
        for id in Array(leases) { end(id) }
        jumps.removeAll(); callback = nil
    }

    func commitJump(_ id: String) {
        guard let jump = jumps.removeValue(forKey: id) else { return }
        guard enabled, foreground, jump.2 > Date() else { end(jump.1); return }
        application.open(jump.0, options: [:]) { _ in
            // A short grace period lets the in-process guest forward its reply.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.end(jump.1) }
        }
    }

    func run(_ name: String, _ args: [String: JSONValue]) async -> PhoneActionResult {
        guard enabled else { return reply("手机控制已关闭。", ok: false) }
        guard foreground else { return reply("请用户返回 App 前台后重试。", ok: false) }
        switch name {
        case "open": return open(args)
        case "intent": return await intent(args)
        case "notify": return await notify(args)
        case "clipboard":
            if let value = args["set"]?.string, args["get"] == nil { UIPasteboard.general.string = value; return reply("已写入剪贴板。") }
            if args["get"]?.bool == true, args["set"] == nil { return reply(UIPasteboard.general.string ?? "剪贴板没有文字。") }
            return reply("请指定 set 文字或 get:true。", ok: false)
        case "shortcut": return shortcut(args)
        case "handoff": return reply("请用户在 App 中完成交接确认。")
        default: return reply("不支持的手机操作。", ok: false)
        }
    }

    // MARK: Jumps

    private func end(_ id: UIBackgroundTaskIdentifier) {
        if id != .invalid, leases.remove(id) != nil { application.endBackgroundTask(id) }
    }

    private func prepare(_ url: URL, _ message: String) -> PhoneActionResult {
        guard application.canOpenURL(url) else { return reply("目标 App 未安装或系统无法打开此链接，请用户手动操作。", ok: false) }
        let id = UUID().uuidString
        final class Lease: @unchecked Sendable { var task = UIBackgroundTaskIdentifier.invalid }
        let lease = Lease()
        lease.task = application.beginBackgroundTask(withName: "phone-result") { [weak self] in
            MainActor.assumeIsolated { self?.jumps.removeValue(forKey: id); self?.end(lease.task) }
        }
        let task = lease.task
        if task != .invalid { leases.insert(task) }
        jumps[id] = (url, task, Date().addingTimeInterval(5))
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if let stale = self?.jumps.removeValue(forKey: id) { self?.end(stale.1) }
        }
        return reply(message, deferred: id)
    }

    private func url(_ scheme: String, host: String = "", path: String = "", _ items: [URLQueryItem] = []) -> URL? {
        var components = URLComponents()
        components.scheme = scheme; components.host = host; components.path = path
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }

    private func open(_ args: [String: JSONValue]) -> PhoneActionResult {
        if let address = text(args, "url"), let url = URL(string: address),
           ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil, url.user == nil, url.password == nil {
            return prepare(url, "将打开链接；请在返回 App 后继续。")
        }
        if args["url"] == nil, let app = text(args, "app", limit: 128) {
            let apps = ["safari": "https://www.apple.com/", "浏览器": "https://www.apple.com/", "地图": "maps://", "maps": "maps://",
                        "apple maps": "maps://", "微信": "weixin://", "wechat": "weixin://", "音乐": "music://", "music": "music://"]
            guard let address = apps[app.lowercased()], let url = URL(string: address) else {
                return reply("不认识此 App。请给出 http/https 链接，或让用户手动打开。", ok: false)
            }
            return prepare(url, "将打开 \(app)；请在返回 App 后继续。")
        }
        return reply("仅允许 http/https 链接或常用 App 名称。拨号、短信和快捷指令请使用专用工具。", ok: false)
    }

    // MARK: Intents

    private func intent(_ args: [String: JSONValue]) async -> PhoneActionResult {
        switch args["kind"]?.string {
        case "alarm", "timer":
            if #available(iOS 26, *) { return await alarm(args) }
            return reply("AlarmKit 需要 iOS 26 或更新系统；请用户手动设置闹钟/计时器。", ok: false)
        case "calendar": return await calendar(args)
        case "reminder": return await reminder(args)
        case "dial":
            guard let number = text(args, "number", limit: 64), number.range(of: #"^\+?[0-9 ()-]{1,60}$"#, options: .regularExpression) != nil,
                  let url = URL(string: "tel:" + number.filter { $0.isNumber || $0 == "+" }) else { return reply("电话号码无效。", ok: false) }
            return prepare(url, "将打开系统拨号确认，尚未拨出。")
        case "sms_draft":
            guard MFMessageComposeViewController.canSendText(), let body = text(args, "text"), let top = topController() else {
                return reply("当前设备不能创建短信草稿（模拟器不支持短信）。", ok: false)
            }
            let composer = MFMessageComposeViewController(); composer.body = body
            if let number = text(args, "number", limit: 64) { composer.recipients = [number] }
            composer.messageComposeDelegate = self
            top.present(composer, animated: true)
            return reply("已打开短信草稿，尚未发送；由用户在系统界面确认。")
        case "share":
            guard let value = text(args, "text"), let top = topController() else { return reply("分享内容不可用。", ok: false) }
            let controller = UIActivityViewController(activityItems: [value], applicationActivities: nil)
            controller.popoverPresentationController?.sourceView = top.view
            controller.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
            top.present(controller, animated: true)
            return reply("已打开系统分享面板，尚未分享；由用户选择目标并确认。")
        case "navigate": return navigate(args)
        case "settings":
            guard args["page"] == nil || ["home", "app_notifications"].contains(args["page"]?.string ?? ""), args["app"] == nil,
                  let url = URL(string: UIApplication.openSettingsURLString) else { return reply("iOS 只允许打开本 App 自身的系统设置。", ok: false) }
            return prepare(url, "将打开本 App 的系统设置。")
        default:
            return reply("iOS 不支持这种系统事务，请使用 handoff 请用户手动完成。", ok: false)
        }
    }

    private func navigate(_ args: [String: JSONValue]) -> PhoneActionResult {
        let destination = text(args, "destination", limit: 1024)
        let lat = args["lat"]?.double, lng = args["lng"]?.double
        let hasCoordinate = lat != nil && lng != nil && lat!.isFinite && lng!.isFinite && (-90...90).contains(lat!) && (-180...180).contains(lng!)
        guard hasCoordinate || destination != nil else { return reply("请提供目的地，或一对有效的 GCJ-02 经纬度。", ok: false) }
        let mode = args["mode"]?.string ?? "drive"
        let preferred = args["map"]?.string ?? "amap"
        let query = destination ?? "\(lat!),\(lng!)"
        var selected: URL?
        var name = "Apple 地图"
        let amapMode = ["walk": "2", "transit": "1", "ride": "3"][mode] ?? "0"
        let amapItems = [URLQueryItem(name: "sourceApplication", value: "DSH"), URLQueryItem(name: "dname", value: query),
                         URLQueryItem(name: "dlat", value: lat.map { String($0) }), URLQueryItem(name: "dlon", value: lng.map { String($0) }),
                         URLQueryItem(name: "dev", value: "0"), URLQueryItem(name: "t", value: amapMode)]
        if preferred != "apple", preferred != "baidu", let candidate = url("iosamap", host: "path", amapItems), application.canOpenURL(candidate) {
            selected = candidate; name = "高德地图"
        }
        let baiduMode = ["walk": "walking", "transit": "transit", "ride": "riding"][mode] ?? "driving"
        let baiduItems = [URLQueryItem(name: "destination", value: hasCoordinate ? "latlng:\(lat!),\(lng!)|name:\(query)" : query),
                          URLQueryItem(name: "coord_type", value: "gcj02"), URLQueryItem(name: "mode", value: baiduMode), URLQueryItem(name: "src", value: "DSH")]
        if selected == nil, preferred != "apple", let candidate = url("baidumap", host: "map", path: "/direction", baiduItems), application.canOpenURL(candidate) {
            selected = candidate; name = "百度地图"
        }
        if selected == nil {
            selected = url("https", host: "maps.apple.com", path: "/", [
                URLQueryItem(name: hasCoordinate ? "daddr" : "q", value: hasCoordinate ? "\(lat!),\(lng!)" : query),
                URLQueryItem(name: "dirflg", value: mode == "walk" ? "w" : mode == "transit" ? "r" : "d")])
        }
        guard let selected else { return reply("无法生成地图链接。", ok: false) }
        return prepare(selected, "将打开\(name)\(hasCoordinate ? "导航" : "搜索")；请用户确认具体目的地。返回 App 后继续。")
    }

    private func date(_ raw: JSONValue?) -> Date? {
        guard let value = raw?.string, value.count <= 80 else { return nil }
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX"); parser.calendar = Calendar(identifier: .gregorian)
            parser.timeZone = .current; parser.isLenient = false; parser.dateFormat = format
            if let date = parser.date(from: value) { return date }
        }
        return nil
    }

    private func calendar(_ args: [String: JSONValue]) async -> PhoneActionResult {
        let ticket = operation
        guard let title = text(args, "title", limit: 1024), let begin = date(args["begin"]),
              let finish = args["end"] == nil ? begin.addingTimeInterval(3600) : date(args["end"]), finish > begin else {
            return reply("日程标题或起止时间无效。", ok: false)
        }
        do {
            guard try await store.requestWriteOnlyAccessToEvents() else { return reply("日历写入权限未获允许，请用户在系统设置授权。", ok: false) }
            guard enabled, operation == ticket else { return reply("日程操作已取消。", ok: false) }
            guard let calendar = store.defaultCalendarForNewEvents else { return reply("系统没有可写入的默认日历，请用户先在日历 App 建立日历。", ok: false) }
            let event = EKEvent(eventStore: store)
            event.calendar = calendar; event.title = title; event.startDate = begin; event.endDate = finish
            event.isAllDay = args["all_day"]?.bool == true
            event.location = args["location"]?.string; event.notes = args["description"]?.string
            try store.save(event, span: .thisEvent, commit: true)
            return reply("已写入日程：\(title)，\(begin.formatted(date: .abbreviated, time: .shortened))。")
        } catch {
            return reply("系统未能保存日程，请检查日历权限和默认日历后重试。", ok: false)
        }
    }

    private func reminder(_ args: [String: JSONValue]) async -> PhoneActionResult {
        let ticket = operation
        guard let title = text(args, "title", limit: 1024), let begin = date(args["begin"]) else {
            return reply("请提供提醒标题和有效的 begin 日期时间。", ok: false)
        }
        do {
            guard try await store.requestFullAccessToReminders() else { return reply("提醒事项权限未获允许，请用户在系统设置授权。", ok: false) }
            guard enabled, operation == ticket else { return reply("提醒操作已取消。", ok: false) }
            guard let calendar = store.defaultCalendarForNewReminders() else {
                return reply("系统没有默认提醒事项列表，请用户先在提醒事项 App 建立列表。", ok: false)
            }
            let item = EKReminder(eventStore: store)
            item.calendar = calendar; item.title = title; item.notes = args["description"]?.string
            item.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: begin)
            item.addAlarm(EKAlarm(absoluteDate: begin))
            try store.save(item, commit: true)
            return reply("已添加提醒：\(title)，\(begin.formatted(date: .abbreviated, time: .shortened))。")
        } catch {
            return reply("系统未能保存提醒，请检查提醒事项权限及默认列表。", ok: false)
        }
    }

    private func notify(_ args: [String: JSONValue]) async -> PhoneActionResult {
        let ticket = operation
        guard let title = text(args, "title", limit: 1024), let body = text(args, "text") else { return reply("通知标题或正文无效。", ok: false) }
        let allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard enabled, operation == ticket else { return reply("通知操作已取消。", ok: false) }
        guard allowed else { return reply("通知权限未获允许。", ok: false) }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: "phone." + UUID().uuidString, content: content, trigger: nil))
            return reply("已提交本地通知。")
        } catch {
            return reply("系统未能提交本地通知。", ok: false)
        }
    }

    @available(iOS 26, *) private struct Metadata: AlarmMetadata {}
    @available(iOS 26, *) private func alarm(_ args: [String: JSONValue]) async -> PhoneActionResult {
        let ticket = operation
        let schedule: Alarm.Schedule
        if args["kind"]?.string == "timer" {
            guard let seconds = args["seconds"]?.int, (1...86400).contains(seconds) else { return reply("计时秒数必须为 1–86400。", ok: false) }
            // Alert-only schedule: no countdown Live Activity is advertised.
            schedule = .fixed(Date().addingTimeInterval(Double(seconds)))
        } else {
            guard let hour = args["hour"]?.int, let minute = args["minute"]?.int, (0...23).contains(hour), (0...59).contains(minute) else {
                return reply("闹钟时间无效。", ok: false)
            }
            let days = args["days"]?.integers ?? []
            guard days.allSatisfy({ (1...7).contains($0) }) else { return reply("重复星期无效。", ok: false) }
            let weekdays: [Locale.Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
            schedule = .relative(.init(time: .init(hour: hour, minute: minute),
                                       repeats: days.isEmpty ? .never : .weekly(days.map { weekdays[$0 - 1] })))
        }
        guard let manager = alarms.manager else { return reply("AlarmKit 未能设置提醒；请检查系统权限后重试，或让用户手动设置。", ok: false) }
        do {
            guard try await manager.requestAuthorization() == .authorized else {
                return reply("闹钟权限未获允许，请用户在系统设置授权。", ok: false)
            }
            guard enabled, operation == ticket else { return reply("闹钟操作已取消。", ok: false) }
            let title = args["message"]?.string ?? "DSH"
            let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title),
                                                stopButton: AlarmButton(text: LocalizedStringResource(stringLiteral: stopTitle),
                                                                        textColor: .white, systemImageName: "stop.circle"))
            let attributes = AlarmAttributes<Metadata>(presentation: AlarmPresentation(alert: alert), metadata: Metadata(), tintColor: .blue)
            _ = try await manager.schedule(id: UUID(), configuration: .alarm(schedule: schedule, attributes: attributes))
            return reply("已在系统 AlarmKit 设置\(args["kind"]?.string == "timer" ? "计时提醒" : "闹钟")。")
        } catch {
            return reply("AlarmKit 未能设置提醒；请检查系统权限后重试，或让用户手动设置。", ok: false)
        }
    }

    // MARK: Shortcuts

    private func shortcut(_ args: [String: JSONValue]) -> PhoneActionResult {
        guard let name = args["name"]?.string else {
            return reply("允许的快捷指令：" + shortcuts.sorted().joined(separator: "、")
                         + (shortcutResult.isEmpty ? "" : "\n最近回调：" + shortcutResult))
        }
        guard shortcuts.contains(name), name.count <= 128 else { return reply("此快捷指令未被用户手动加入白名单。", ok: false) }
        let nonce = UUID().uuidString
        func callbackURL(_ state: String) -> String {
            url(Self.callbackScheme, host: "phone-shortcut", [URLQueryItem(name: "nonce", value: nonce), URLQueryItem(name: "state", value: state)])!.absoluteString
        }
        let items = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "input", value: "text"),
                     URLQueryItem(name: "text", value: args["input"]?.string ?? ""),
                     URLQueryItem(name: "x-success", value: callbackURL("success")),
                     URLQueryItem(name: "x-error", value: callbackURL("error")),
                     URLQueryItem(name: "x-cancel", value: callbackURL("cancel"))]
        guard let target = url("shortcuts", host: "x-callback-url", path: "/run-shortcut", items) else { return reply("无法生成快捷指令链接。", ok: false) }
        callback = (nonce, name, Date().addingTimeInterval(600)); shortcutResult = ""
        return prepare(target, "将运行白名单快捷指令「\(name)」；返回 App 后调用 shortcut（不带 name）查询回调结果。")
    }

    /// x-callback-url return from the Shortcuts app. Returns true when handled.
    func receive(_ url: URL) -> Bool {
        guard url.scheme == Self.callbackScheme, url.host == "phone-shortcut" else { return false }
        guard enabled, let pending = callback, pending.until > Date(), shortcuts.contains(pending.name),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.first(where: { $0.name == "nonce" })?.value == pending.nonce else { return true }
        callback = nil
        let state = items.first(where: { $0.name == "state" })?.value ?? "unknown"
        let output = items.first(where: { $0.name == "result" })?.value ?? items.first(where: { $0.name == "output" })?.value ?? ""
        shortcutResult = pending.name + ": " + state + (output.isEmpty ? "" : "\n" + String(output.prefix(16384)))
        return true
    }

    nonisolated func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        Task { @MainActor in controller.dismiss(animated: true) }
    }

    // MARK: Capabilities

    func capabilities() async -> [String: String] {
        let settings = await center.notificationSettings()
        func eventStatus(_ status: EKAuthorizationStatus) -> String {
            switch status {
            case .notDetermined: "notDetermined"
            case .denied, .restricted: "denied"
            case .writeOnly: "writeOnly"
            default: "authorized"
            }
        }
        var alarm = "unsupported"
        if #available(iOS 26, *), let manager = alarms.manager {
            switch manager.authorizationState {
            case .authorized: alarm = "authorized"
            case .denied: alarm = "denied"
            default: alarm = "notDetermined"
            }
        }
        let notify = settings.authorizationStatus == .notDetermined ? "notDetermined"
            : [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) ? "authorized" : "denied"
        return ["alarm": alarm, "calendar": eventStatus(EKEventStore.authorizationStatus(for: .event)),
                "reminder": eventStatus(EKEventStore.authorizationStatus(for: .reminder)), "notify": notify,
                "shortcut": application.canOpenURL(URL(string: "shortcuts://")!) ? "available" : "unavailable"]
    }

    private func topController() -> UIViewController? {
        let scene = application.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? application.connectedScenes.first as? UIWindowScene
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
