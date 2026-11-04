// SPDX-License-Identifier: AGPL-3.0-or-later
// Confirmation policy; same rules as 原 Flutter 版 lib/phone_ios/safety.dart. The
// ask/task/always wire values match Android's ConfirmMode.
import Foundation

public enum ConfirmMode: String, CaseIterable, Sendable { case ask, task, always }

public struct SafetyDecision: Equatable, Sendable {
    public var denied: String?
    public var confirm = false
    public var allowTask = false
}

public final class PhoneSafety: @unchecked Sendable {
    private let lock = NSLock()
    private var waived: Set<String> = []
    private var seenShortcuts: Set<String> = []

    public init() {}
    public func revoke() { lock.withLock { waived.removeAll() } }
    public func waive(_ scope: String) { lock.withLock { _ = waived.insert(scope) } }
    public func shortcutCompleted(_ name: String) { lock.withLock { _ = seenShortcuts.insert(name) } }

    public func check(name: String, args: [String: Any], mode: ConfirmMode,
                      shortcuts: Set<String>, trustedScope: String?) -> SafetyDecision {
        if name == "shortcut" {
            // Listing the whitelist (no name) needs no confirmation.
            guard let shortcut = args["name"] as? String else { return SafetyDecision() }
            guard shortcuts.contains(shortcut) else {
                return SafetyDecision(denied: "此快捷指令不在白名单。请用户在设置 → 手机控制中手动添加，工具不能修改白名单。")
            }
            if !lock.withLock({ seenShortcuts.contains(shortcut) }) { return SafetyDecision(confirm: true) }
        }
        let kind = args["kind"] as? String
        if name == "handoff" || (name == "clipboard" && (args["get"] as? Bool) == true)
            || (name == "intent" && ["dial", "sms_draft", "share"].contains(kind ?? "")) {
            return SafetyDecision(confirm: true)
        }
        switch mode {
        case .ask:
            return SafetyDecision(confirm: true)
        case .task:
            // No identity supplied by the model can mint a task waiver. Missing or
            // ambiguous local Host running-edge evidence asks again on each call.
            let scoped = trustedScope.map { scope in lock.withLock { waived.contains(scope) } } ?? false
            return SafetyDecision(confirm: !scoped, allowTask: trustedScope != nil)
        case .always:
            return SafetyDecision()
        }
    }
}
