// SPDX-License-Identifier: AGPL-3.0-or-later
// Run rows assembled as in DSH Go app/lib/ui/chat/{chat_rows,chat_list}.dart.
import DSHClient
import SwiftUI

struct ChatMessageList: View {
    @Environment(AppSession.self) private var chat
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.appReduceMotion) private var reduceMotion
    let width: CGFloat
    var initiallyOpen = false
    var openTrace: (TurnTrace) -> Void
    @State private var diff: DiffSelection?
    @State private var wrapsDiff = true

    private struct DiffSelection: Identifiable {
        let trace: TurnTrace
        let index: Int
        var id: Int { trace.id }
    }

    var body: some View {
        let items = chat.transcript.items
        let turns = chat.transcript.turnTraces
        let rows = ChatRunRow.derive(items: items, turns: turns, running: chat.transcript.turnRunning,
                                     fold: preferences.foldCompletedTurns)
        let toolSpans = Dictionary(turns.flatMap(\.spans).compactMap { span -> (String, TraceSpan)? in
            guard let id = span.callId, span.kind != .approval || span.open else { return nil }
            return (id, span)
        }, uniquingKeysWith: { old, new in old.kind == .approval && old.open ? old : new })
        let bubbleWidth = (min(width, Space.readingWidth) - 2 * Space.gutter) * 0.82
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.inTurn) {
                    Color.clear.frame(height: 64)
                    if items.isEmpty && !chat.transcript.loadingSession {
                        EmptyChatView { prompt in Task { await chat.transcript.send(prompt) } }
                            .frame(minHeight: 520)
                    }
                    if chat.transcript.loadingSession { ProgressView().frame(maxWidth: .infinity).padding(.top, 40) }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        rowView(row, bubbleWidth: bubbleWidth, spans: toolSpans)
                            .padding(.top, row.isUser && index > 0 ? Space.betweenTurns - Space.inTurn : 0)
                    }
                    if let retry = chat.transcript.retrying, chat.transcript.turnRunning {
                        RetryRow(retry: retry.retry, max: retry.max, code: retry.code).id("retrying")
                    } else if chat.transcript.turnRunning && !items.contains(where: { $0.state == .streaming }) {
                        WhaleTail(height: 22).opacity(0.7).id("working")
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, Space.gutter)
                .frame(maxWidth: Space.readingWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: items.last) { scrollToBottom(proxy) }
            .onChange(of: turns.last?.endSeq) { if turns.last?.endSeq != nil { scrollToBottom(proxy) } }
        }
        .fullScreenCover(item: $diff) { selection in
            TurnDiffPage(files: selection.trace.changes, initialIndex: selection.index, wraps: $wrapsDiff)
        }
    }

    @ViewBuilder private func rowView(_ row: ChatRunRow, bubbleWidth: CGFloat, spans: [String: TraceSpan]) -> some View {
        switch row {
        case .message(let item, let actions, let trace):
            ChatItemView(item: item, maxBubbleWidth: bubbleWidth, toolSpans: spans,
                         showsActions: actions, footnote: trace, openTrace: openTrace)
        case .process(let items):
            TurnProcessView(items: items, maxBubbleWidth: bubbleWidth, spans: spans, initiallyOpen: initiallyOpen)
        case .footnote(let trace):
            TurnFootnote(trace: trace) { openTrace(trace) }
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .changes(let trace):
            TurnChangeCard(files: trace.changes) { diff = DiffSelection(trace: trace, index: $0) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : AppMotion.standard) { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}
