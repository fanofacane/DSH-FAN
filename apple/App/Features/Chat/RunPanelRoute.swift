// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/lib/ui/chat/{chat_screen,usage_sheet,trajectory_sheet,step_detail_page}.dart.
import DSHClient
import SwiftUI

struct TraceReference: Hashable {
    let session: String?
    let startSeq: Int
}

enum RunPanelRoute: Identifiable, Equatable {
    case usage
    case trajectory(TraceReference)

    var id: String {
        switch self {
        case .usage: "usage"
        case .trajectory(let reference): "trajectory-\(reference.session ?? "")-\(reference.startSeq)"
        }
    }
}

struct RunTrajectoryRoute: View {
    let reference: TraceReference
    @Environment(AppSession.self) private var chat
    @State private var selected: TraceStep?

    private var trace: TurnTrace? {
        guard reference.session == chat.transcript.currentSessionId else { return nil }
        return chat.transcript.turnTraces.first { $0.startSeq == reference.startSeq }
    }

    var body: some View {
        TrajectoryPanel(trace: trace, skew: chat.transcript.clockSkew ?? 0) { selected = $0 }
            .presentationDetents([.fraction(0.62), .fraction(0.86)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Radius.xl)
            .fullScreenCover(item: $selected) { selected in
                NavigationStack {
                    detail(selected)
                        .navigationDestination(for: TraceStep.self) { detail($0) }
                }
            }
    }

    private func detail(_ step: TraceStep) -> some View {
        RunStepPage(step: step, trace: trace, items: trace == nil ? [] : chat.transcript.items,
                    skew: chat.transcript.clockSkew ?? 0)
    }
}

struct RunUsageRoute: View {
    @Environment(AppSession.self) private var chat
    @Environment(HostStore.self) private var hosts
    @Environment(EngineModel.self) private var engine
    @State private var balance: RunBalanceStore
    @AppStorage("chat.lowBalanceThreshold") private var limit = RunBalance.defaultLimit
    @State private var trace: TraceReference?
    private let openTrace: ((TurnTrace) -> Void)?

    init(balance: RunBalanceStore? = nil, openTrace: ((TurnTrace) -> Void)? = nil) {
        _balance = State(initialValue: balance ?? RunBalanceStore())
        self.openTrace = openTrace
    }

    var body: some View {
        UsagePanel(metrics: chat.control.projection.metrics, turns: chat.transcript.turnTraces,
                   historyHasMore: chat.transcript.historyHasMore,
                   host: hosts.activeHost?.name ?? String(localized: "This phone"),
                   model: chat.transcript.sessionModel?.id ?? chat.connection.selectedModel?.id,
                   engine: hosts.isRemote ? nil : String(localized: engine.status.phase.titleResource),
                   balance: balance.value(for: chat.connection, isRemote: hosts.isRemote),
                   balanceLimit: $limit) { turn in
            if let openTrace { openTrace(turn) }
            else { trace = TraceReference(session: chat.transcript.currentSessionId, startSeq: turn.startSeq) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(chat.connection.generation)-\(chat.connection.state == .ready)") {
            await balance.refresh(chat.connection, isRemote: hosts.isRemote)
        }
        .sheet(item: $trace) { RunTrajectoryRoute(reference: $0) }
    }
}

extension TraceReference: Identifiable {
    var id: Self { self }
}
