// SPDX-License-Identifier: AGPL-3.0-or-later
// Transcript rows styled after 原 Flutter 版 lib/ui/chat (user_bubble.dart, tool_row.dart,
// thinking row, assistant body). See 原 Flutter 版 test/chat/goldens/conversation_*.png.
import DSHClient
import SwiftUI

struct ChatItemView: View {
    @Environment(AppSession.self) private var chat
    let item: ChatItem
    let maxBubbleWidth: CGFloat
    @State private var selecting = false
    var toolSpans: [String: TraceSpan] = [:]
    var showsActions = false
    var footnote: TurnTrace?
    var openTrace: (TurnTrace) -> Void = { _ in }

    var body: some View {
        switch item.role {
        case .user: userBubble.contextMenu { menu }.sheet(isPresented: $selecting) { SelectTextSheet(text: item.text) }
        case .assistant: assistant.contextMenu { menu }.sheet(isPresented: $selecting) { SelectTextSheet(text: item.text) }
        case .notice: notice
        }
    }

    /// Message menu (message_menu.dart): copy and select; then the actions
    /// that open a new chat (retry, branch, edit and resend).
    @ViewBuilder private var menu: some View {
        if !item.text.isEmpty {
            Button { UIPasteboard.general.string = item.text } label: { Label("Copy", systemImage: "doc.on.doc") }
            Button { chat.transcript.quote(item.text) } label: { Label("Quote", systemImage: "quote.bubble") }
            ShareLink(item: item.text) { Label("Share", systemImage: "square.and.arrow.up") }
            Button { selecting = true } label: { Label("Select text", systemImage: "selection.pin.in.out") }
        }
        if chat.transcript.retryPrompt(for: item) != nil {
            Section("Opens a new chat") {
                Button { Task { await chat.transcript.retry(item) } } label: { Label("Regenerate", systemImage: "arrow.clockwise") }
            }
        }
        if chat.transcript.canBranch(item) {
            Button { Task { await chat.transcript.branch(after: item) } } label: { Label("Branch from here", systemImage: "arrow.triangle.branch") }
        }
        if chat.transcript.canEdit(item) {
            Section("Opens a new chat") {
                Button { Task { await chat.transcript.edit(item) } } label: { Label("Edit and resend", systemImage: "pencil") }
            }
        }
    }

    @ViewBuilder private var attachmentImages: some View {
        if let sessionId = chat.transcript.currentSessionId {
            ForEach(Array(item.images.enumerated()), id: \.offset) { _, image in
                MessagePhoto(source: .attachment(image, sessionId))
            }
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                if item.imageCount > 0 {
                    HStack(spacing: 4) {
                        Glyph(glyph: AppIcon.image, size: 12)
                        Text("\(item.imageCount) image(s)")
                    }
                    .type(.labelSmall).foregroundStyle(DS.inkFaint)
                }
                attachmentImages
                if !item.text.isEmpty {
                    Text(item.text)
                        .type(.body)
                        .foregroundStyle(DS.ink)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(DS.userBubble, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                        .opacity(item.state == .pending ? 0.72 : 1)
                }
            }
            .frame(maxWidth: maxBubbleWidth, alignment: .trailing)
        }
    }

    private var assistant: some View {
        VStack(alignment: .leading, spacing: 0) {
            process
            attachmentImages
            if !item.text.isEmpty {
                MarkdownView(source: item.text)
                    .padding(.top, !item.reasoning.isEmpty || !item.tools.isEmpty ? Space.sm : 0)
                if showsActions || footnote != nil {
                    ReplyActions(text: item.text, trace: footnote, open: openTrace) { menu }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var process: some View {
        if !item.reasoning.isEmpty {
            ThinkingRow(text: item.reasoning, streaming: item.state == .streaming && item.text.isEmpty)
        }
        let groups = toolGroups
        ForEach(groups, id: \.first?.id) { group in
            if group.count >= 3 {
                ChatToolBatch(tools: group, spans: toolSpans,
                              live: item.state == .streaming || group.contains { toolSpans[$0.id]?.open == true })
            } else {
                ForEach(group) { ToolRowView(tool: $0, span: toolSpans[$0.id]) }
            }
        }
    }

    private var toolGroups: [[ToolRow]] {
        var groups: [[ToolRow]] = []
        var batch: [ToolRow] = []
        for tool in item.tools {
            let waiting = toolSpans[tool.id]?.kind == .approval
            if tool.name == "ask_user_question" || waiting {
                if !batch.isEmpty { groups.append(batch); batch = [] }
                groups.append([tool])
            } else {
                batch.append(tool)
            }
        }
        if !batch.isEmpty { groups.append(batch) }
        return groups
    }

    @ViewBuilder private var notice: some View {
        if case .failed(let code) = item.state {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Glyph(glyph: AppIcon.error, size: 16)
                Text(failureText(code)).type(.bodyMedium)
            }
            .foregroundStyle(DS.danger)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(DS.dangerContainer.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        } else if !item.text.isEmpty {
            Text(verbatim: item.text).type(.bodyMedium).foregroundStyle(DS.inkMuted).textSelection(.enabled)
        }
    }

    private func failureText(_ code: String) -> String {
        switch code {
        case "auth", "MISSING_CREDENTIAL": String(localized: "The API key was rejected. Check it in settings.")
        case "rate-limit": String(localized: "Too many requests. Try again shortly.")
        case "max-tokens": String(localized: "The reply hit the length limit.")
        case "E_NO_REPLY": String(localized: "The model returned no reply.")
        case "SERVER", "server", "overloaded": String(localized: "The model service is busy. Try again in a moment.")
        case "TIMEOUT", "timeout": String(localized: "The model request timed out. Try again.")
        case "TRANSPORT", "network": String(localized: "Couldn’t reach the model service. Check the network.")
        case "RATE_LIMIT": String(localized: "Too many requests. Try again shortly.")
        case "E_NO_EARLIER_HISTORY": String(localized: "There’s no earlier history to branch from")
        case "session/fork-unavailable": String(localized: "Couldn’t branch the chat here")
        case "E_DELETE_UNSUPPORTED": String(localized: "This host can’t delete chats")
        default: String(localized: "Request failed: \(code)")
        }
    }
}

/// Whole message text, selectable (chatSelectText).
struct SelectTextSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text).type(.body).foregroundStyle(DS.ink).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(Space.gutter)
            }
            .navigationTitle("Select text").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Copy all") { UIPasteboard.general.string = text; dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 「思考 · 摘要 ⌄」, expandable.
struct ThinkingRow: View {
    @Environment(\.designTheme) private var theme
    let text: String
    var streaming = false
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    IconTile(glyph: DshGlyph.lightbulb, tint: theme.accent, fill: theme.accentContainer)
                    Text("Thinking").type(.bodyMedium).foregroundStyle(DS.inkMuted)
                    Text("·").foregroundStyle(DS.inkGhost)
                    Text(firstLine).type(.bodyMedium).foregroundStyle(DS.inkFaint).lineLimit(1)
                    Spacer(minLength: 4)
                    Glyph(glyph: open ? DshGlyph.caretUp : DshGlyph.caretDown, size: 14).foregroundStyle(DS.inkFaint)
                }
            }
            .buttonStyle(.plain)
            .frame(minHeight: RunLayout.processHeight)
            if open {
                Text(text)
                    .type(.bodySmall).foregroundStyle(DS.inkMuted)
                    .textSelection(.enabled)
                    .padding(.leading, 32)
            }
        }
        .opacity(streaming ? 0.85 : 1)
    }

    private var firstLine: String {
        text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}

/// Small rounded square behind a 14pt glyph (tool / thinking rows).
struct IconTile: View {
    let glyph: DshGlyph
    var tint: Color = DS.inkMuted
    var fill: Color = DS.surfaceHigh
    var body: some View {
        Glyph(glyph: glyph, size: 14)
            .foregroundStyle(tint)
            .frame(width: RunLayout.processLead, height: RunLayout.processLead)
            .background(fill, in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
    }
}

/// 「读取 · 原 Flutter 版 lib/…」 one-liner; tap to see arguments and result.
struct ToolRowView: View {
    @Environment(\.designTheme) private var theme
    let tool: ToolRow
    var span: TraceSpan?
    @State private var open = false

    var body: some View {
        let presentation = ToolPresenterRegistry.present(tool, args: tool.args, theme: theme)
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    IconTile(glyph: presentation.style.glyph, tint: presentation.style.tint, fill: presentation.style.fill)
                    Text(LocalizedStringKey(presentation.style.label)).type(.bodyMedium).foregroundStyle(DS.inkMuted)
                    if !presentation.summary.isEmpty {
                        Text("·").foregroundStyle(DS.inkGhost)
                        Text(presentation.summary).font(Mono.font(13, scale: theme.readingScale)).foregroundStyle(DS.inkFaint).lineLimit(1).truncationMode(.tail)
                    }
                    Spacer(minLength: 4)
                    if span?.kind == .approval {
                        Glyph(glyph: AppIcon.warning, size: 14).foregroundStyle(DS.warn)
                    } else if tool.failed || span?.failed == true {
                        Glyph(glyph: AppIcon.error, size: 14).foregroundStyle(DS.danger)
                    } else if span?.cutShort == true {
                        Glyph(glyph: AppIcon.stopped, size: 14).foregroundStyle(DS.inkFaint)
                    } else if tool.result == nil {
                        ProgressView().controlSize(.mini).tint(theme.accent)
                    } else if let counts = editCounts {
                        DiffCounts(added: counts.added, removed: counts.removed)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(minHeight: RunLayout.processHeight)
            if open {
                if !tool.arguments.isEmpty { CodeBlockView(language: "arguments", code: prettyArguments) }
                if let result = tool.result { CodeBlockView(language: String(localized: "result"), code: String(result.prefix(4000))) }
            }
        }
    }

    private var editCounts: (added: Int, removed: Int)? {
        let changes = tool.presentation.changes
        guard !changes.isEmpty else { return nil }
        let lines = changes.flatMap(\.lines)
        return (lines.filter { $0.hasPrefix("+") }.count, lines.filter { $0.hasPrefix("-") }.count)
    }

    private var prettyArguments: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let args = tool.args
        guard let data = try? encoder.encode(args),
              !args.isEmpty else { return tool.arguments }
        return String(decoding: data, as: UTF8.self)
    }
}

/// The DeepSeek whale tail (still frame of 原 Flutter 版 assets/whale/whale_1.png), tinted.
/// Brand placeholder: replace before release (see THIRD_PARTY_NOTICES.md).
struct WhaleTail: View {
    var height: CGFloat = 40
    var tint: Color = DS.whale
    var body: some View {
        Group {
            if let image = UIImage(named: "whale_1.png") {
                Image(uiImage: image.withRenderingMode(.alwaysTemplate))
                    .resizable().scaledToFit()
                    .foregroundStyle(tint)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
