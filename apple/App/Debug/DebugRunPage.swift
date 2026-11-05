// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/test/chat/{run_info_golden_test,chat_features_test}.dart.
#if DEBUG
import DSHClient
import SwiftUI

struct DebugRunPage: View {
    let route: Route
    enum Route { case chat, diff, dock, goal, usage, trajectory, modelStep, toolStep }
    @Environment(AppSession.self) private var chat
    @State private var loaded = false
    @State private var draft = ""
    @State private var images: [PickedImage] = []
    @State private var voice = VoiceInput()
    @FocusState private var focused: Bool
    private var fixture: String { DebugPageRegistry.argument("-dsh-screen-fixture") ?? "finished" }

    var body: some View {
        Group {
            if loaded {
                switch route {
                case .chat: conversation
                case .usage:
                    panel(height: 604) {
                        UsagePanel(metrics: chat.control.projection.metrics, turns: chat.transcript.turnTraces,
                                   historyHasMore: false, host: "本机", model: "deepseek-v4-pro", engine: nil,
                                   balance: previewBalance, balanceLimit: .constant(5), openTrace: { _ in })
                    }
                case .trajectory:
                    panel(height: 498) {
                        TrajectoryPanel(trace: chat.transcript.turnTraces.last, skew: 0) { _ in }
                    }
                case .modelStep, .toolStep:
                    if let turn = chat.transcript.turnTraces.first,
                       let span = turn.spans.first(where: { route == .modelStep ? $0.kind == .model : $0.callId == "c-test" && $0.kind == .tool }) {
                        RunStepPage(step: TraceStep(span), trace: turn, items: chat.transcript.items)
                    }
                case .dock:
                    VStack(spacing: Space.md) {
                        Spacer()
                        Text("登录按钮连点会重复提交，是因为提交期间没有禁用按钮，而且接口没有做幂等。先给提交加一把锁，再补一个连点测试。测试跑完之后，我会更新 README 里的运行说明。")
                            .type(.body).padding(.horizontal, Space.gutter)
                        composer
                    }
                    .background { AppBackdrop() }
                case .goal:
                    if let goal = DebugDockFixtures.goal(phase: fixture == "goal-blocked" ? "blocked" : "active") {
                        VStack(spacing: 0) {
                            Spacer()
                            GoalDockActions(goal: goal, previewClear: fixture == "goal-clear")
                                .frame(height: fixture == "goal-clear" ? 320 : 450)
                                .clipShape(.rect(topLeadingRadius: Radius.xl, topTrailingRadius: Radius.xl))
                        }
                        .background { AppBackdrop() }
                    }
                case .diff:
                    if let first = chat.transcript.turnTraces.first, !first.changes.isEmpty {
                        TurnDiffPage(files: first.changes, initialIndex: fixture == "changes" ? 1 : 0, wraps: .constant(true))
                    }
                }
            }
        }
        .environment(\.runClockOverride, DebugDockFixtures.now)
        .task {
            guard !loaded else { return }
            load()
            loaded = true
        }
    }

    private var conversation: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                ChatMessageList(width: geometry.size.width, initiallyOpen: fixture == "finished-open") { _ in }
                ChatHeaderView(openDrawer: {}, files: .constant(false), agents: .constant(false),
                               schedules: .constant(false), openUsage: {})
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        }
    }

    private var composer: some View {
        ChatComposerView(draft: $draft, images: $images, composerFocused: $focused, voice: voice,
                         openWorkspace: {}, openImages: {}, startDictation: {}, submit: {}, openTrace: { _ in },
                         lowBalance: fixture == "low-balance" ? previewBalance : nil,
                         showsWorkspace: false, previewFolded: fixture == "dock-folded", previewTodoOpen: fixture == "dock-open")
    }

    private var previewBalance: RunBalance {
        if fixture == "low-balance" { return RunBalance(currency: "CNY", paid: Decimal(string: "3.20"), bonus: nil) }
        return RunBalance(currency: "CNY", paid: 100, bonus: 10)
    }

    private func panel<Content: View>(height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .bottom) {
            conversation.padding(.top, 22).padding(.bottom, 24)
            DS.scrim
            VStack(spacing: 0) {
                Capsule().fill(DS.inkGhost).frame(width: 36, height: 4).padding(.vertical, Space.sm)
                content()
            }
            .frame(height: height)
            .background(DS.surface)
            .clipShape(.rect(topLeadingRadius: Radius.xl, topTrailingRadius: Radius.xl))
        }
    }

    private func load() {
        let id = "run-info-fixture"
        chat.transcript.newChat()
        chat.transcript.currentSessionId = id
        chat.sessionList.insert(SessionSummary(id: id, title: "修复登录重复提交", updatedAt: .now,
                                               running: fixture == "running", blank: false, agentAvailable: false))
        let changesFixture = fixture == "changes" || fixture == "usage" || fixture == "low-balance"
        let input = changesFixture ? DebugRunFrames.fileChanges : DebugRunFrames.runInfo
        let limit: Int
        switch fixture {
        case "approval": limit = 24
        case "streaming": limit = 42
        case "running", "changes", "usage", "low-balance", "dock-stack", "dock-folded", "dock-spread", "dock-open": limit = Int.max
        default: limit = 39
        }
        var records: [LogEvent] = []
        var facts: [RunFact] = []
        for line in input.split(separator: "\n") {
            for frame in DSHClient.decodeFollowFixture(Data(line.utf8)) {
                switch frame {
                case .timeline(let batch, _): facts += batch.filter { $0.id <= limit }
                case .snapshot(let batch, _): records += batch.filter { $0.seq <= limit }
                case .event(let event) where event.seq <= limit: records.append(event)
                default: break
                }
            }
        }
        chat.transcript.handle(.timeline(facts, replace: true))
        chat.transcript.handle(.snapshot(records, hasMore: false))
        if fixture == "approval" {
            let frame: JSONValue = ["type": "waterfall", "eventId": "debug-approval", "agentId": .string(id), "event": "approval/request",
                                    "request": ["toolName": "bash", "callId": "c-test", "displayReason": ["zh-CN": "运行登录测试需要确认"]]]
            if let data = try? JSONEncoder().encode(frame), let request = HostRequest.decodeFixture(data) {
                chat.requests.receive(request)
            }
        }
        if fixture == "compaction",
           let fact = RunFact(["type": "compaction/start", "seq": 61, "time": DebugDockFixtures.now.timeIntervalSince1970 * 1000 - 1800]) {
            chat.transcript.handle(.timeline([fact], replace: false))
        }
        if fixture == "streaming" {
            chat.transcript.handle(.reasoningDelta("先检查控制器和调用点，确定重复提交发生在哪里。"))
            chat.transcript.handle(.textDelta("我先看一下登录控制器。正在检查 submit() 里的异步调用。"))
        }
        let todos = fixture.hasPrefix("dock-") ? DebugDockFixtures.running : fixture == "running" ?
            Array(DebugDockFixtures.running.prefix(4)) + [TodoItem(content: "跑一遍测试确认", status: "in_progress")] : DebugDockFixtures.done
        let normalized = fixture == "running" ? todos.enumerated().map {
            TodoItem(content: $0.element.content, status: $0.offset < 4 ? "completed" : "in_progress")
        } : todos
        var values: [String: JSONValue] = [:]
        if !changesFixture && fixture != "streaming" && fixture != "approval" {
            values["todos"] = .array(normalized.map { ["content": .string($0.content), "status": .string($0.status ?? "")] })
        }
        if fixture.hasPrefix("dock-") { values["goal"] = DebugDockFixtures.goalValue() }
        if fixture == "usage" || fixture == "low-balance" {
            values["tokenUsage"] = ["uncachedInputTokens": 18_240, "cacheReadTokens": 52_736, "cacheWriteTokens": 0, "outputTokens": 3_410]
            values["contextPressure"] = ["pressureTokens": 61_800, "projectedTokens": 62_100, "contextWindow": 1_000_000]
            values["contextBreakdown"] = ["systemTokens": 1_467, "toolsTokens": 5_157, "messageTokens": 54_876]
            values["sessionStats"] = ["turns": 2]
        }
        let frame: JSONValue = ["type": "baseline", "value": ["projections": .object([id: ["values": .object(values)]])]]
        if let data = try? JSONEncoder().encode(frame) { chat.control.state.applyFixture(data) }
    }
}
#endif
