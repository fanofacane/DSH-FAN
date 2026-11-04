// SPDX-License-Identifier: AGPL-3.0-or-later
// Guest overlay for phone control; same structure as 原 Flutter 版 ios/Runner/Phone/PhoneGuestFiles.swift
// (itself following Android PhoneGuest.kt). Runs on the runtime worker after boot,
// before DSH starts, through the guest VFS only.
import DSHRuntime
import Foundation

enum PhoneGuestFiles {
    static let patch = "/opt/dsh-app/phone/phone.patch.yml"
    static let config = "/var/lib/dsh-app/phone/bridge.json"
    private static let relayPath = "/opt/dsh-app/phone/relay.cjs"
    private static let agents = "/root/.dsh/AGENTS.md"
    private static let begin = "<!-- dsh-fan:phone-ios:start -->"
    private static let end = "<!-- dsh-fan:phone-ios:end -->"
    /// Markers written before the DSH Fan rename; still removed so no stale section remains.
    private static let legacy = ("<!-- dsh-go:phone-ios:start -->", "<!-- dsh-go:phone-ios:end -->")

    struct Launch: Sendable {
        let configJSON: String
        let relay: String
        let patch: String
    }

    /// Writes (launch != nil) or removes (nil) the overlay and AGENTS.md section.
    static func prepare(_ launch: Launch?) throws {
        for path in ["/opt/dsh-app", "/opt/dsh-app/phone", "/var/lib/dsh-app", "/var/lib/dsh-app/phone", "/root/.dsh"] {
            guard GuestFiles.mkdir(path, mode: path == "/var/lib/dsh-app/phone" ? 0o700 : 0o755) else {
                throw RuntimeError("E_PHONE_GUEST_DIRECTORY")
            }
        }
        guard GuestFiles.unlink(config) else { throw RuntimeError("E_PHONE_GUEST_CONFIG") }
        if let launch {
            guard launch.relay.utf8.count < 65536, launch.patch.utf8.count < 16384, launch.configJSON.utf8.count < 1024,
                  GuestFiles.write(relayPath, launch.relay, mode: 0o644),
                  GuestFiles.write(patch, launch.patch, mode: 0o644),
                  GuestFiles.write(config, launch.configJSON, mode: 0o600),
                  GuestFiles.mode(config) & 0o777 == 0o600 else { throw RuntimeError("E_PHONE_GUEST_PERMISSIONS") }
        }
        let old = GuestFiles.readText(agents, maxBytes: 1024 * 1024)
        // Never replace an unreadable or oversize user file with an empty one.
        if old == nil && GuestFiles.mode(agents) >= 0 { throw RuntimeError("E_PHONE_AGENTS_READ") }
        var text = old ?? ""
        for (open, close) in [(begin, end), legacy] {
            if let start = text.range(of: open), let finish = text.range(of: close, range: start.upperBound..<text.endIndex) {
                text.removeSubrange(start.lowerBound..<finish.upperBound)
            }
        }
        if launch != nil {
            text += "\n" + begin + "\n## iOS 手机控制\n\n- 用 mcp__phone__open / intent / notify / clipboard / shortcut / handoff 调用系统能力。iOS 不支持读屏和点击其他 App。\n- 快捷指令只能运行用户在设置里手动加入白名单的名称。拒绝或权限不足时请说明原因，不能绕过确认。\n- open、navigate、shortcut 会进入后台，应放在任务最后一步；结果先返回，再跳转。需要登录、支付、验证码或手动操作时用 handoff。\n- 时间按手机本地时区。不要臆测成功，以工具返回的系统结果为准。\n" + end + "\n"
        }
        guard text == old || GuestFiles.write(agents, text, mode: 0o644) else { throw RuntimeError("E_PHONE_AGENTS_WRITE") }
    }
}
