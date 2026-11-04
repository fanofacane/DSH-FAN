// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import Foundation
import Observation

@MainActor extension TranscriptStore {
    func executeCommand(_ line: String) async {
        guard !busy else { return }
        let name = line.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        guard ComposerCompletion.commandAllowed(name) else { appendNotice("E_COMMAND_UNAVAILABLE"); return }
        do {
            let id = try await ensureSession()
            let result = try await CommandsAPI(client: requireClient()).execute(agentId: id, line: line.trimmingCharacters(in: .whitespacesAndNewlines))
            guard result.kind == "success" else { throw DSHError("E_COMMAND_REFUSED") }
            if let text = result.text, !text.isEmpty {
                committed.append(ChatItem(id: "command-" + UUID().uuidString, role: .notice, text: text))
            }
            await actions?.refreshSessions()
        } catch { appendNotice(appErrorCode(error)) }
    }
    func stop() async {
        guard let client, let currentSessionId else { return }
        try? await client.cancel(sessionId: currentSessionId)
    }
    func quote(_ text: String) {
        composerInsertion = text.components(separatedBy: .newlines).map { "> " + $0 }.joined(separator: "\n") + "\n\n"
        requestComposerFocus()
    }
    func openNotificationSession(_ id: String) async {
        await actions?.refreshSessions()
        guard let session = sessions.first(where: { $0.id == id }) else { appendNotice("E_NOTIFICATION_SESSION_MISSING"); return }
        await open(session)
    }
    func canBranch(_ item: ChatItem) -> Bool {
        guard !busy, item.role == .assistant, let seq = item.seq else { return false }
        return ForkPoints.afterReply(events, replySeq: seq) != nil
    }
    func retryPrompt(for item: ChatItem) -> ChatItem? {
        guard !busy, item.role == .assistant, item.seq != nil, let index = committed.firstIndex(where: { $0.id == item.id }),
              committed[(index + 1)...].allSatisfy({ $0.role == .notice }) else { return nil }
        guard let prompt = committed[..<index].last(where: { $0.role == .user }), prompt.imageCount == 0,
              !prompt.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return prompt
    }
    func canEdit(_ item: ChatItem) -> Bool { !busy && item.role == .user && item.seq != nil }
    func branch(after item: ChatItem) async {
        guard let seq = item.seq, let cut = ForkPoints.afterReply(events, replySeq: seq) else { return }
        _ = await fork(at: cut)
    }
    func retry(_ item: ChatItem) async {
        guard let prompt = retryPrompt(for: item), await forkBefore(prompt) else { return }
        await send(prompt.text)
    }
    func edit(_ item: ChatItem) async {
        guard await forkBefore(item) else { return }
        incomingDraft = SharedDraft(text: item.text, images: [])
    }
    func forkBefore(_ prompt: ChatItem) async -> Bool {
        guard let seq = prompt.seq else { return false }
        guard let cut = ForkPoints.beforePrompt(events, promptSeq: seq) else {
            appendNotice("E_NO_EARLIER_HISTORY"); return false
        }
        return await fork(at: cut)
    }
    func fork(at cut: Int) async -> Bool {
        guard let client, let source = currentSessionId else { return false }
        do {
            let outcome = try await client.forkAt(source, atSeq: cut, sourceTitle: currentTitle)
            await actions?.refreshSessions()
            let summary = sessions.first { $0.id == outcome.sessionId }
                ?? SessionSummary(id: outcome.sessionId, title: outcome.title, updatedAt: Date(), running: false,
                                  blank: false, agentAvailable: false)
            actions?.insertSession(summary)
            await open(summary)
            return true
        } catch {
            appendNotice(appErrorCode(error))
            return false
        }
    }
    func imageData(_ reference: MessageImageReference, sessionId: String) async throws -> Data {
        if let data = reference.data { return data }
        guard let attachmentId = reference.attachmentId else { throw DSHError("E_IMAGE_UNAVAILABLE") }
        return try await FilesAPI(client: requireClient()).attachment(sessionId: sessionId, attachmentId: attachmentId)
    }
    private func requireClient() throws -> DSHClient { guard let client else { throw DSHError("E_NOT_CONNECTED") }; return client }
}
