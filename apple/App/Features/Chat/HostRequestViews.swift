// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import SwiftUI

/// Shown above the composer while a tool call waits for permission
/// (chat/widgets/approval_card.dart: warm rim, shield, command chip, two keys).
struct ApprovalCard: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    let approval: ApprovalRequest
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Glyph(glyph: AppIcon.approval, size: 20).foregroundStyle(DS.warn)
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(DS.ink)
            }
            if let text = approval.describe(), !text.isEmpty {
                Text(text).type(.bodyMedium).foregroundStyle(DS.inkMuted).lineLimit(6).textSelection(.enabled)
            }
            if let command {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "$").foregroundStyle(DS.inkFaint)
                    Text(command).foregroundStyle(DS.ink).lineLimit(4)
                }
                .font(Mono.font(14, scale: theme.readingScale))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.codeWell, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            HStack(spacing: 10) {
                Button { decide(false) } label: {
                    Text("Deny").font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(DS.outline.opacity(0.6)))
                }
                Button { decide(true) } label: {
                    Text("Allow once").font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(theme.accent, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
            }
            .buttonStyle(.plain)
            .disabled(working)
        }
        .padding(16)
        .glass(.card, radius: Radius.lg)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(DS.warn.opacity(0.45), lineWidth: 1))
    }

    private var tool: ToolRow? {
        guard let callId = approval.callId else { return nil }
        return chat.transcript.items.flatMap(\.tools).last { $0.id == callId }
    }

    private var command: String? {
        guard let tool, ["bash", "pwsh"].contains(tool.name),
              let args = (try? JSONValue(data: Data(tool.arguments.utf8)))?.object,
              let command = args["command"]?.string, !command.isEmpty else { return nil }
        return command
    }

    private var title: LocalizedStringKey {
        command != nil ? "Allow this command to run?" : "Allow \(approval.toolName)?"
    }

    private func decide(_ allow: Bool) {
        working = true
        Task { await chat.requests.respond(approval, allow: allow); working = false }
    }
}

/// The `ask_user_question` tool: one page with every question.
struct QuestionSheet: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    @Environment(\.dismiss) private var dismiss
    let request: QuestionRequest
    @State private var selected: [String: Set<String>] = [:]
    @State private var custom: [String: String] = [:]

    var body: some View {
        ZStack {
            AppBackdrop(glow: false)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Glyph(glyph: DshGlyph.chatCenteredDots, size: 22).foregroundStyle(DS.dusk)
                        Text("The model has a question").font(.system(size: 20, weight: .bold)).foregroundStyle(DS.ink)
                    }
                    .padding(.horizontal, 8).padding(.top, 24).padding(.bottom, 18)
                    ForEach(request.questions) { question in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(question.header ?? question.question).font(.system(size: 16, weight: .semibold)).foregroundStyle(DS.ink)
                                .padding(.horizontal, 8)
                            if question.header != nil {
                                Text(question.question).type(.bodyMedium).foregroundStyle(DS.inkMuted).padding(.horizontal, 8)
                            }
                            if let detail = question.detail, !detail.isEmpty {
                                MarkdownView(source: detail).padding(.horizontal, 8)
                            }
                            VStack(spacing: 0) {
                                ForEach(Array(question.options.enumerated()), id: \.element) { index, option in
                                    if index > 0 { RowDivider() }
                                    Button { toggle(question, option.label) } label: {
                                        SettingsRow(title: LocalizedStringKey(option.label), subtitle: option.description) {
                                            Glyph(glyph: isOn(question, option.label)
                                                  ? (question.multiSelect ? DshGlyph.checkSquareFill : DshGlyph.radioButton)
                                                  : (question.multiSelect ? DshGlyph.square : DshGlyph.circle), size: 20)
                                                .foregroundStyle(isOn(question, option.label) ? theme.accent : DS.inkGhost)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                                if !question.options.isEmpty { RowDivider() }
                                TextField("Other answer", text: Binding(get: { custom[question.id] ?? "" },
                                                                        set: { custom[question.id] = $0 }), axis: .vertical)
                                    .font(.system(size: 16)).padding(16)
                            }
                            .glass(.card, radius: Radius.lg)
                        }
                        .padding(.bottom, 22)
                    }
                }
                .padding(.horizontal, Space.gutter)
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    MistButton(title: "Skip", kind: .secondary) { Task { await chat.requests.decline(request) }; dismiss() }
                    MistButton(title: "Send") { submit() }.disabled(!complete).opacity(complete ? 1 : 0.5)
                }
                .padding(.horizontal, Space.gutter).padding(.vertical, 12)
                .background(.bar)
            }
        }
        .interactiveDismissDisabled()
        .presentationDetents([.large])
    }

    private func isOn(_ question: UserQuestion, _ label: String) -> Bool { selected[question.id]?.contains(label) == true }

    private func toggle(_ question: UserQuestion, _ label: String) {
        var set = selected[question.id] ?? []
        if question.multiSelect { if set.contains(label) { set.remove(label) } else { set.insert(label) } }
        else { set = [label] }
        selected[question.id] = set
    }

    private var complete: Bool {
        request.questions.allSatisfy { !(selected[$0.id] ?? []).isEmpty || !(custom[$0.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func submit() {
        let answers = request.questions.map { question -> QuestionAnswer in
            let text = (custom[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let picks = question.options.map(\.label).filter { isOn(question, $0) }
            return QuestionAnswer(id: question.id, selected: picks, custom: text.isEmpty ? nil : text)
        }
        Task { await chat.requests.answer(request, answers) }
        dismiss()
    }
}
