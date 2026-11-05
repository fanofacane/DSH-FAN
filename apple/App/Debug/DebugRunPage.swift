// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/test/chat/{run_info_golden_test,chat_features_test}.dart.
#if DEBUG
import DSHClient
import SwiftUI

struct DebugRunPage: View {
    let route: Route
    enum Route { case chat, diff }
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
                case .diff:
                    if let first = chat.transcript.turnTraces.first, !first.changes.isEmpty {
                        TurnDiffPage(files: first.changes, initialIndex: fixture == "changes" ? 1 : 0, wraps: .constant(true))
                    }
                }
            }
        }
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ChatComposerView(draft: $draft, images: $images, composerFocused: $focused, voice: voice,
                                 openWorkspace: {}, openImages: {}, startDictation: {}, submit: {})
            }
        }
    }

    private func load() {
        let id = "run-info-fixture"
        chat.transcript.newChat()
        chat.transcript.currentSessionId = id
        chat.sessionList.insert(SessionSummary(id: id, title: "修复登录重复提交", updatedAt: .now,
                                               running: fixture == "running", blank: false, agentAvailable: false))
        let input = fixture == "changes" ? DebugRunFrames.fileChanges : DebugRunFrames.runInfo
        let limit = fixture == "running" || fixture == "changes" ? Int.max : 39
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
    }
}
#endif
