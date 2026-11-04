// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import Foundation
import Observation

@MainActor @Observable final class HostRequestStore {
    private let shared: RequestSessionState
    private(set) var approvals: [ApprovalRequest] = []
    private(set) var questions: [QuestionRequest] = []
    private(set) var runningSessions: Set<String> {
        get { shared.runningSessions }
        set { shared.runningSessions = newValue }
    }
    private let context: SessionContext
    @ObservationIgnored private weak var actions: (any SessionActions)?
    private var client: DSHClient? { context.client }
    private let hosts: any HostProviding
    private let phone: any PhoneControlling
    private let notifications: any TaskNotifying
    init(context: SessionContext, actions: any SessionActions, hosts: any HostProviding, phone: any PhoneControlling, notifications: any TaskNotifying) {
        self.context = context; shared = context.requestState; self.actions = actions
        self.hosts = hosts; self.phone = phone; self.notifications = notifications
    }
    var currentApproval: ApprovalRequest? { approvals.first { $0.sessionId == context.currentSessionId } }
    var currentQuestion: QuestionRequest? { questions.first { $0.sessionId == context.currentSessionId } }
    func reset() { approvals = []; questions = []; runningSessions = [] }
    func resetRunning() { runningSessions = [] }
    func receive(_ request: HostRequest) {
        switch request {
        case .approval(let value):
            if !approvals.contains(where: { $0.id == value.id }) {
                approvals.append(value)
                let host = self.hosts.activeHost?.id
                Task { await self.notifications.notify(.attention, eventId: value.id, sessionId: value.sessionId, hostId: host) }
            }
        case .question(let value):
            if !questions.contains(where: { $0.id == value.id }) {
                questions.append(value)
                let host = self.hosts.activeHost?.id
                Task { await self.notifications.notify(.attention, eventId: value.id, sessionId: value.sessionId, hostId: host) }
            }
        case .cancelled(let id):
            approvals.removeAll { $0.id == id }; questions.removeAll { $0.id == id }
        case .sessionStatus(let id, let running):
            self.phone.sessionStatus(id, running: running)
            if running { runningSessions.insert(id) }
            else if runningSessions.remove(id) != nil, id != context.currentSessionId {
                let host = self.hosts.activeHost?.id
                Task {
                    await self.notifications.notify(.finished, eventId: id + "-" + UUID().uuidString, sessionId: id, hostId: host)
                    if !self.context.hasRunningTasks { self.notifications.finishGrace() }
                }
            }
        }
    }
    func respond(_ approval: ApprovalRequest, allow: Bool) async {
        approvals.removeAll { $0.id == approval.id }
        do { try await client?.respondApproval(approval, allow: allow) }
        catch { actions?.appendNotice(appErrorCode(error)) }
    }
    func answer(_ question: QuestionRequest, _ answers: [QuestionAnswer]) async {
        questions.removeAll { $0.id == question.id }
        do { try await client?.answerQuestion(question, answers: answers) }
        catch { actions?.appendNotice(appErrorCode(error)) }
    }
    func decline(_ question: QuestionRequest) async {
        questions.removeAll { $0.id == question.id }
        try? await client?.declineQuestion(question)
    }
}

/// Shared values are readable through SessionContext; only this store file can write them.
@MainActor @Observable final class RequestSessionState {
    fileprivate(set) var runningSessions: Set<String> = []
}
