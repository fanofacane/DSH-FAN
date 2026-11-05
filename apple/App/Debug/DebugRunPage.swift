// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/test/chat/{run_info_golden_test,chat_features_test}.dart.
#if DEBUG
import DSHClient
import SwiftUI

struct DebugRunPage: View {
    let route: Route
    enum Route { case chat, diff, dock, goal }
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
                               insights: .constant(false), schedules: .constant(false))
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        }
    }

    private var composer: some View {
        ChatComposerView(draft: $draft, images: $images, composerFocused: $focused, voice: voice,
                         openWorkspace: {}, openImages: {}, startDictation: {}, submit: {}, openTrace: { _ in },
                         showsWorkspace: false, previewFolded: fixture == "dock-folded", previewTodoOpen: fixture == "dock-open")
    }

    private func load() {
        let id = "run-info-fixture"
        chat.transcript.newChat()
        chat.transcript.currentSessionId = id
        chat.sessionList.insert(SessionSummary(id: id, title: "修复登录重复提交", updatedAt: .now,
                                               running: fixture == "running", blank: false, agentAvailable: false))
        let input = fixture == "changes" ? DebugRunFrames.fileChanges : DebugRunFrames.runInfo
        let limit: Int
        switch fixture {
        case "approval": limit = 24
        case "streaming": limit = 42
        case "running", "changes", "dock-stack", "dock-folded", "dock-spread", "dock-open": limit = Int.max
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
        if fixture != "changes" && fixture != "streaming" && fixture != "approval" {
            values["todos"] = .array(normalized.map { ["content": .string($0.content), "status": .string($0.status ?? "")] })
        }
        if fixture.hasPrefix("dock-") { values["goal"] = DebugDockFixtures.goalValue() }
        let frame: JSONValue = ["type": "baseline", "value": ["projections": .object([id: ["values": .object(values)]])]]
        if let data = try? JSONEncoder().encode(frame) { chat.control.state.applyFixture(data) }
    }
}
#endif
