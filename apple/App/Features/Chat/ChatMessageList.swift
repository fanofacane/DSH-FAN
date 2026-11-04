// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct ChatMessageList: View {
    @Environment(AppSession.self) private var chat
    let width: CGFloat
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.inTurn) {
                    Color.clear.frame(height: 64)
                    if chat.transcript.items.isEmpty && !chat.transcript.loadingSession {
                        EmptyChatView { prompt in Task { await chat.transcript.send(prompt) } }
                            .frame(minHeight: 520)
                    }
                    if chat.transcript.loadingSession { ProgressView().frame(maxWidth: .infinity).padding(.top, 40) }
                    ForEach(Array(chat.transcript.items.enumerated()), id: \.element.id) { index, item in
                        ChatItemView(item: item, maxBubbleWidth: (min(width, Space.readingWidth) - 2 * Space.gutter) * 0.82)
                            .padding(.top, item.role == .user && index > 0 ? Space.betweenTurns - Space.inTurn : 0)
                            .id(item.id)
                    }
                    if let retry = chat.transcript.retrying, chat.transcript.turnRunning {
                        RetryRow(retry: retry.retry, max: retry.max, code: retry.code).id("retrying")
                    } else if chat.transcript.turnRunning && !chat.transcript.items.contains(where: { $0.state == .streaming }) {
                        WhaleTail(height: 22).opacity(0.7).id("working")
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, Space.gutter)
                .frame(maxWidth: Space.readingWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.transcript.items.last) { withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
    }

}
