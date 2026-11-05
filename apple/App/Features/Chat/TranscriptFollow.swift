// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go packages/dsh_client/lib/src/transcript.dart.
import DSHClient
import Foundation
import Observation

@MainActor extension TranscriptStore {
    func startFollow(_ id: String) {
        followReady = false
        followTask = Task { [weak self] in
            guard let self, let client = self.client else { return }
            do {
                for try await event in try await client.follow(sessionId: id) {
                    guard self.currentSessionId == id else { break }
                    self.handle(event)
                }
            } catch {
                if !Task.isCancelled, self.currentSessionId == id {
                    self.turnRunning = false; self.stopping = false; self.draft = nil
                    self.appendNotice(appErrorCode(error))
                }
            }
            self.releaseSnapshotWaiter()
        }
    }
    func waitForSnapshot() async {
        if followReady || followTask == nil { return }
        await withCheckedContinuation { snapshotWaiter = $0 }
    }
    func releaseSnapshotWaiter() {
        let waiter = snapshotWaiter; snapshotWaiter = nil
        waiter?.resume()
    }
    func handle(_ event: ChatEvent) {
        switch event {
        case .snapshot(let records, let more):
            historyHasMore = more
            committed = []; lastSeq = -1; draft = nil; events = []
            for record in records { apply(record) }
            followReady = true; releaseSnapshotWaiter()
        case .timeline(let facts, let replace):
            if replace {
                traceFold = TurnTraceFold()
                for fact in facts.sorted(by: { $0.id < $1.id }) { traceFold.apply(fact) }
            } else {
                for fact in facts {
                    traceFold.apply(fact)
                    if hosts.isRemote {
                        let sample = Date.now.timeIntervalSince(fact.time)
                        if abs(sample) <= 3600 { clockSkew = min(clockSkew ?? sample, sample) }
                    }
                }
            }
        case .event(let record):
            apply(record)
        case .textDelta(let text):
            tokenRate.add(text)
            editDraft { $0.text += text }
        case .reasoningDelta(let text):
            tokenRate.add(text)
            editDraft { $0.reasoning += text }
        case .toolCallDelta(let id, let name, let delta):
            tokenRate.add(delta)
            editDraft { item in
                if let index = item.tools.firstIndex(where: { $0.id == id }) {
                    item.tools[index].arguments += delta
                    if let name { item.tools[index].name = name }
                } else {
                    item.tools.append(ToolRow(id: id, name: name ?? "", arguments: delta))
                }
            }
        case .modelFailure(let kind):
            lastFailure = kind
        }
    }
    func apply(_ record: LogEvent) {
        guard record.seq > lastSeq else { return }
        lastSeq = record.seq
        events.append(record)
        switch record {
        case .userMessage(let seq, let message):
            guard message.sourceKind == "user" else { return }
            if let id = message.requestId { pending.removeAll { $0.requestId == id } }
            committed.append(ChatItem(id: "e\(seq)", role: .user, text: message.text, imageCount: message.imageCount, images: message.images, seq: seq))
        case .assistantMessage(let seq, _, _, let message, _):
            draft = nil; retrying = nil
            guard !message.text.isEmpty || !message.reasoning.isEmpty || !message.toolCalls.isEmpty else { return }
            committed.append(ChatItem(id: "e\(seq)", role: .assistant, text: message.text, reasoning: message.reasoning,
                                      tools: message.toolCalls.map { ToolRow(id: $0.id, name: $0.name, arguments: $0.arguments) },
                                      imageCount: message.imageCount, images: message.images, seq: seq))
        case .toolResult(_, let callId, let text, let failed, let presentation):
            for index in committed.indices.reversed() {
                if let tool = committed[index].tools.firstIndex(where: { $0.id == callId }) {
                    committed[index].tools[tool].result = text
                    committed[index].tools[tool].failed = failed
                    committed[index].tools[tool].presentation = presentation
                    break
                }
            }
        case .turnStarted:
            turnRunning = true; stopping = false; tokenRate = RunTokenRate()
        case .turnEnded(_, _, let reason):
            let wasRunning = turnRunning
            turnRunning = false; stopping = false; draft = nil; tokenRate = RunTokenRate()
            let lastRetry = retrying; retrying = nil
            let normal: Set<String> = ["completed", "aborted", "forked", "unknown"]
            if let failure = lastFailure ?? (normal.contains(reason) ? nil : (lastRetry?.code ?? reason)), wasRunning || followReady {
                appendNotice(failure)
            }
            lastFailure = nil
            if followReady, wasRunning, let session = currentSessionId, reason == "completed" || reason == "aborted" || !normal.contains(reason) {
                let kind: TaskNotifications.Kind = reason == "completed" ? .reply : .failed
                let host = self.hosts.activeHost?.id
                Task {
                    await self.notifications.notify(kind, eventId: session + "-" + String(record.seq), sessionId: session, hostId: host)
                    if !self.context.hasRunningTasks { self.notifications.finishGrace() }
                }
            }
            if followReady { Task { await actions?.refreshSessions() } }
        case .attempt:
            draft = nil // DSH may retry; the next attempt streams a fresh draft.
        case .retry(_, let retry, let max, let code):
            draft = nil
            retrying = (retry, max, code)
        case .other:
            break
        }
    }
    func editDraft(_ change: (inout ChatItem) -> Void) {
        var item = draft ?? ChatItem(id: "draft", role: .assistant, state: .streaming)
        change(&item)
        draft = item
    }
    func appendNotice(_ code: String) {
        committed.append(ChatItem(id: "n\(UUID().uuidString)", role: .notice, state: .failed(code)))
    }
    func closeSession() {
        sessionEpoch += 1; sessionCreation?.cancel(); sessionCreation = nil
        followTask?.cancel(); followTask = nil
        releaseSnapshotWaiter()
        currentSessionId = nil; sessionModel = nil; sessionEffort = nil; followReady = false
        traceFold = TurnTraceFold(); historyHasMore = false
        turnRunning = false; sending = false; stopping = false; clockSkew = nil; tokenRate = RunTokenRate()
        lastSeq = -1; lastFailure = nil; events = []; retrying = nil
    }
}
