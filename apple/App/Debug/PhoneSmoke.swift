// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import Darwin
import DSHClient
import DSHPhone
import DSHRuntime
import Foundation

/// Simulator phone-control smoke test (`-dsh-phone-smoke`). Expects phone
/// control enabled with mode `always` (set via `defaults write` before launch)
/// and calendar/reminder access granted with `simctl privacy`. Results in
/// Documents/phone-smoke.json hold states and tool names only.
extension AppSession {
    /// Blocking POSIX client; returns a short status string (no secrets).
    nonisolated static func bridgeSelfTest(_ config: PhoneBridgeServer.LaunchConfig) -> String {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return "socket failed" }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(config.port).bigEndian; address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { return "connect errno \(errno)" }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let lines = "{\"dshPhone\":1,\"token\":\"\(config.token)\"}\n"
            + "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\"}}\n"
            + "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}\n"
        _ = lines.withCString { Darwin.send(fd, $0, strlen($0), 0) }
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while received.filter({ $0 == 10 }).count < 2 {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count <= 0 { return "recv \(count) errno \(errno) after \(received.count) bytes" }
            received.append(contentsOf: buffer[0..<count])
        }
        let text = String(decoding: received, as: UTF8.self)
        return "ok: initialize=\(text.contains("dsh-app-phone")) tools=\(text.contains("\"name\":\"intent\"")) bytes=\(received.count)"
    }

    static var phoneSmokeRequested: Bool { ProcessInfo.processInfo.arguments.contains("-dsh-phone-smoke") }

    func runPhoneSmoke(phone: PhoneController, runtime: any EngineControlling) async {
        var result = SmokeReport()
        func save() {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("phone-smoke.json")
            if let data = try? result.data() {
                try? data.write(to: url, options: .atomic)
            }
        }
        func waitReady(_ seconds: Double) async -> Bool {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                if self.connection.state == .ready, self.transcript.canSend { return true }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            return false
        }
        func turn(_ text: String, label: String) async -> String {
            self.transcript.newChat()
            await self.transcript.send(text)
            try? await Task.sleep(nanoseconds: 500_000_000)
            let end = Date().addingTimeInterval(240)
            while Date() < end, self.transcript.busy || self.transcript.items.contains(where: { $0.state == .pending || $0.state == .streaming }) {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            let tools = self.transcript.items.flatMap(\.tools)
            let reply = self.transcript.items.last { $0.role == .assistant }?.text ?? ""
            result.set(label, JSONValue.object(["tools": .array(tools.map { .string($0.name) }),
                "results": .array(tools.compactMap { $0.result.map { .string(String($0.prefix(60))) } }),
                "replyChars": .integer(reply.count)]))
            save()
            return reply
        }
        result.set("phoneLastError", phone.lastError ?? "")
        result.set("resources", ["relay": Bundle.main.url(forResource: "relay", withExtension: "cjs") != nil,
                               "patch": Bundle.main.url(forResource: "phone.patch", withExtension: "yml") != nil])
        result.set("catalogLoaded", phone.available)
        result.set("catalogSha256", PhoneCatalog.sha256)
        result.set("enabled", phone.enabled)
        result.set("mode", phone.mode.rawValue)
        let engineStatus = await runtime.status()
        // Safe mode skips the phone overlay; record it so a FAIL is not misread as a bridge bug.
        result.set("engineMode", engineStatus.mode.rawValue)
        result.set("engineSafeState", engineStatus.safeState)
        save()
        guard await waitReady(60) else { result.set("result", "FAIL"); result.set("reason", "not ready"); save(); return }
        // Native side alone: connect to our own bridge, hello + initialize + tools/list.
        if let config = phone.debugConfig {
            result.set("bridgeSelfTest", await Task.detached { Self.bridgeSelfTest(config) }.value)
        } else {
            result.set("bridgeSelfTest", "no bridge config")
        }
        result.set("bridgeEvents", phone.debugBridgeEvents)
        result.set("controllerTrace", phone.debugTrace)
        result.set("engineLog", await runtime.logTail(lines: 400)
            .filter { $0.range(of: "phone|relay|mcp", options: [.regularExpression, .caseInsensitive]) != nil }
            .suffix(20).map { String($0.prefix(200)) })
        save()

        _ = await turn("请用手机控制在明天下午3点添加一个日程，标题为“DSH测试会议”。完成后简短告诉我结果。", label: "calendar")
        _ = await turn("请用手机控制提醒我本周五上午9点交报告，标题为“交报告”。完成后简短告诉我结果。", label: "reminder")
        let withTools = await turn("你当前能否调用名为 mcp__phone__intent 的工具？只回答“有”或“没有”，不要调用任何工具。", label: "toolsVisibleWhenOn")
        result.set("toolsVisibleWhenOn", withTools.contains("有") && !withTools.contains("没有"))

        await phone.setEnabled(false)
        result.set("disabledError", phone.lastError ?? "")
        let reconnected = await waitReady(180)
        result.set("reconnectedAfterDisable", reconnected)
        if reconnected {
            let without = await turn("你当前能否调用名为 mcp__phone__intent 的工具？只回答“有”或“没有”，不要调用任何工具。", label: "toolsVisibleWhenOff")
            result.set("toolsHiddenWhenOff", without.contains("没有"))
        }
        let calendar = result["calendar"]?["results"]?.strings ?? []
        let reminder = result["reminder"]?["results"]?.strings ?? []
        let calendarOK = calendar.contains { $0.contains("已写入日程") }
        let reminderOK = reminder.contains { $0.contains("已添加提醒") }
        result.set("calendarOK", calendarOK); result.set("reminderOK", reminderOK)
        result.set("result", calendarOK && reminderOK && result["toolsVisibleWhenOn"]?.bool == true
            && result["toolsHiddenWhenOff"]?.bool == true ? "PASS" : "FAIL")
        save()
    }
}
#endif
