// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import Foundation

/// Simulator message-menu smoke test (`-dsh-menu-smoke`, this phone's engine):
/// one short turn, then branch, retry and edit. Results
/// (Documents/menu-smoke.json) hold ids, counts and states only.
extension AppSession {
    static var menuSmokeRequested: Bool { ProcessInfo.processInfo.arguments.contains("-dsh-menu-smoke") }

    func runMenuSmoke() async {
        var result = SmokeReport()
        func save() {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("menu-smoke.json")
            if let data = try? result.data() {
                try? data.write(to: url, options: .atomic)
            }
        }
        func idle(_ seconds: Double = 180) async {
            let end = Date().addingTimeInterval(seconds)
            try? await Task.sleep(nanoseconds: 800_000_000)
            while Date() < end, self.transcript.busy || self.transcript.loadingSession || self.transcript.items.contains(where: { $0.state == .pending || $0.state == .streaming }) {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        guard self.transcript.canSend else { result.set("result", "FAIL"); result.set("reason", "cannot send"); save(); return }
        self.transcript.newChat()
        await self.transcript.send("Reply with exactly one word: pong")
        await idle()
        let source = self.transcript.currentSessionId
        guard let reply = self.transcript.items.last(where: { $0.role == .assistant && $0.seq != nil }),
              let prompt = self.transcript.items.last(where: { $0.role == .user && $0.seq != nil }) else {
            result.set("result", "FAIL"); result.set("reason", "no turn"); save(); return
        }
        result.set("canBranch", self.transcript.canBranch(reply))
        result.set("canRetry", self.transcript.retryPrompt(for: reply) != nil)
        result.set("canEdit", self.transcript.canEdit(prompt))

        await self.transcript.branch(after: reply)
        await idle(20)
        result.set("branchNewSession", self.transcript.currentSessionId != nil && self.transcript.currentSessionId != source)
        result.set("branchItems", self.transcript.items.filter { $0.role != .notice }.count)
        result.set("branchTitle", self.transcript.currentTitle ?? "")
        save()

        await self.transcript.open(self.sessionList.sessions.first { $0.id == source }!)
        await idle(20)
        if let last = self.transcript.items.last(where: { $0.role == .assistant && $0.seq != nil }) {
            await self.transcript.retry(last)
            await idle()
            result.set("retryNewSession", self.transcript.currentSessionId != source)
            result.set("retryReplies", self.transcript.items.filter { $0.role == .assistant && $0.seq != nil }.count)
            result.set("retryUsers", self.transcript.items.filter { $0.role == .user }.count)
        }
        save()

        await self.transcript.open(self.sessionList.sessions.first { $0.id == source }!)
        await idle(20)
        if let user = self.transcript.items.last(where: { $0.role == .user && $0.seq != nil }) {
            await self.transcript.edit(user)
            // Read before the chat screen moves it into the composer.
            result.set("editDraftRestored", self.transcript.incomingDraft?.text == user.text)
            await idle(20)
            result.set("editNewSession", self.transcript.currentSessionId != source)
            result.set("editItems", self.transcript.items.filter { $0.role != .notice }.count)
        }
        result.set("notices", self.transcript.items.filter { $0.role == .notice }.count)
        let ok = result["branchNewSession"]?.bool == true && result["retryNewSession"]?.bool == true
            && result["editNewSession"]?.bool == true && result["editDraftRestored"]?.bool == true
        result.set("result", ok ? "PASS" : "FAIL")
        save()
    }
}
#endif
