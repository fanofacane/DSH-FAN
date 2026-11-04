// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import DSHClient
import Foundation
import UIKit

/// Simulator chat smoke test (`-dsh-chat-smoke`). If no key is configured, a
/// test key is taken from the launch environment (`SIMCTL_CHILD_DSH_TEST_KEY`)
/// and handed to the engine's credential store. Results
/// (Documents/chat-smoke.json) hold states and counts only: never the key,
/// the token or message text.
extension AppSession {
    static var smokeRequested: Bool { ProcessInfo.processInfo.arguments.contains("-dsh-chat-smoke") }

    func runChatSmoke() async {
        var result = SmokeReport()
        func save() {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("chat-smoke.json")
            if let data = try? result.data() {
                try? data.write(to: url, options: .atomic)
            }
        }
        func waitIdle(_ seconds: Double) async {
            let end = Date().addingTimeInterval(seconds)
            try? await Task.sleep(nanoseconds: 500_000_000)
            while Date() < end, self.transcript.busy || self.transcript.items.contains(where: { $0.state == .pending || $0.state == .streaming }) {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        @discardableResult
        func turn(_ text: String, images: [PromptImage] = [], label: String) async -> String {
            let began = Date()
            let before = self.transcript.items.count
            await self.transcript.send(text, images: images)
            await waitIdle(240)
            let added = Array(self.transcript.items.dropFirst(before))
            let reply = added.last { $0.role == .assistant }
            let notice = added.last { $0.role == .notice }
            var row = SmokeReport()
            row.set("ms", Int(Date().timeIntervalSince(began) * 1000))
            row.set("replyChars", reply?.text.count ?? 0)
            row.set("userEchoed", added.contains { $0.role == .user && $0.state == .done })
            if case .failed(let code)? = notice?.state { row.set("state", "FAIL"); row.set("code", code) }
            else { row.set("state", (reply?.text.isEmpty == false) ? "PASS" : "FAIL") }
            result.set(label, row); save()
            return reply?.text ?? ""
        }
        result.set("connection", "\(self.connection.state)")
        if !self.connection.keyConfigured {
            // SIMCTL_CHILD_DSH_TEST_KEY: process environment of this test launch only.
            let supplied = ProcessInfo.processInfo.environment["DSH_TEST_KEY"] ?? ""
            result.set("keySaved", supplied.isEmpty ? false : await self.connection.saveKey(supplied))
        } else {
            result.set("keySaved", "already-configured")
        }
        result.set("selected", self.connection.selectedModel?.id ?? "")
        save()
        guard self.transcript.canSend else { result.set("result", "FAIL"); result.set("reason", "cannot send"); save(); return }

        self.transcript.newChat()
        await turn("你好，请用一句话回复。", label: "first")
        let markdown = await turn("请严格用 Markdown 回答：一个二级标题，三个无序列表项，再给一个 python 代码块（打印 hello）。不要多余解释。",
                                  label: "markdown")
        let blocks = MarkdownParser.parse(markdown)
        result.set("markdownBlocks", JSONValue.object([
            "heading": .bool(blocks.contains { if case .heading = $0 { return true }; return false }),
            "list": .integer(blocks.filter { if case .listItem = $0 { return true }; return false }.count),
            "code": .bool(blocks.contains { if case .code = $0 { return true }; return false }),
        ]))
        let firstSession = self.transcript.currentSessionId
        save()

        self.transcript.newChat()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            UIColor.systemRed.setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 96, y: 96, width: 320, height: 320))
        }
        if let jpeg = image.jpegData(compressionQuality: 0.85) {
            let reply = await turn("图片里的圆是什么颜色？只回答颜色。",
                                   images: [PromptImage(mediaType: "image/jpeg", data: jpeg, name: "circle.jpg")], label: "image")
            result.set("imageMentionsRed", reply.contains("红") || reply.lowercased().contains("red"))
        }

        // Reopen the first session from the list and check its history came back.
        await self.sessionList.refreshSessions()
        self.transcript.newChat()
        if let firstSession, let summary = self.sessionList.sessions.first(where: { $0.id == firstSession }) {
            await self.transcript.open(summary)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            result.set("reopen", JSONValue.object([
                "sessionsListed": .integer(self.sessionList.sessions.count),
                "userItems": .integer(self.transcript.items.filter { $0.role == .user }.count),
                "assistantItems": .integer(self.transcript.items.filter { $0.role == .assistant }.count),
                "titled": .bool(summary.title != nil),
            ]))
        } else {
            result.set("reopen", ["found": false])
        }
        // M3: tool approval round trip, permission presets, rename, delete.
        result.set("permissionPresets", self.control.permissionPresets.map(\.id))
        result.set("enginePermissionDefault", self.control.enginePermissionDefault)
        self.transcript.newChat()
        final class Counter { var approvals = 0 }
        let counter = Counter()
        let watcher = Task { @MainActor in
            while !Task.isCancelled {
                if let approval = self.requests.currentApproval { counter.approvals += 1; await self.requests.respond(approval, allow: true) }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        await turn("请调用命令执行工具运行 `echo dsh-approval-test`，然后把输出原样告诉我。", label: "tool")
        watcher.cancel()
        let tools = self.transcript.items.flatMap(\.tools)
        result.set("toolRun", JSONValue.object([
            "approvalsSeen": .integer(counter.approvals), "toolCalls": .integer(tools.count), "toolNames": .array(tools.map { .string($0.name) }),
            "resultHasMarker": .bool(tools.contains { $0.result?.contains("dsh-approval-test") == true }),
        ]))
        let toolSession = self.transcript.currentSessionId
        await self.sessionList.refreshSessions()
        if let toolSession, let summary = self.sessionList.sessions.first(where: { $0.id == toolSession }) {
            await self.sessionList.rename(summary, to: "M3 重命名测试")
            result.set("renamed", self.sessionList.sessions.first { $0.id == toolSession }?.title == "M3 重命名测试")
            if let renamed = self.sessionList.sessions.first(where: { $0.id == toolSession }) {
                let error = await self.sessionList.delete(renamed)
                await self.sessionList.refreshSessions()
                result.set("deleted", error == nil && !self.sessionList.sessions.contains { $0.id == toolSession })
                if let error { result.set("deleteError", error) }
            }
        }
        save()

        let rows = ["first", "markdown", "image"].compactMap { result[$0]?.object }
        let reopen = result["reopen"]?.object
        let reopened = (reopen?["userItems"]?.int ?? 0) >= 2 && (reopen?["assistantItems"]?.int ?? 0) >= 2
        result.set("result", rows.count == 3 && rows.allSatisfy { $0["state"]?.string == "PASS" } && reopened ? "PASS" : "FAIL")
        save()
    }
}
#endif
