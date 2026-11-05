// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/lib/ui/chat/widgets/{turn_process,tool_row,stream_row}.dart.
import DSHClient
import SwiftUI

struct RunProcessRow<Content: View>: View {
    let label: String
    let glyph: DshGlyph
    var style: ToolStyle? = nil
    var failed = 0
    var initiallyOpen = false
    var didToggle: (Bool) -> Void = { _ in }
    @ViewBuilder let content: () -> Content
    @State private var toggled: Bool?
    @Environment(\.appReduceMotion) private var reduceMotion

    private var open: Bool { toggled ?? initiallyOpen }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                let next = !open
                toggled = next
                didToggle(next)
            } label: {
                HStack(spacing: Space.sm) {
                    if let style { IconTile(glyph: style.glyph, tint: style.tint, fill: style.fill) }
                    else { Glyph(glyph: glyph, size: 18).frame(width: RunLayout.processLead) }
                    Text(label).type(.bodyMedium).lineLimit(1)
                    Spacer(minLength: 0)
                    if failed > 0 {
                        Glyph(glyph: AppIcon.error, size: 14).foregroundStyle(DS.danger)
                        Text(failed.formatted()).font(Mono.font(12)).foregroundStyle(DS.danger)
                    }
                    Glyph(glyph: AppIcon.expand, size: 16)
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .animation(reduceMotion ? nil : AppMotion.collapse, value: open)
                }
                .foregroundStyle(DS.inkFaint)
                .frame(minHeight: RunLayout.processHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(open ? "Expanded" : "Collapsed"))
            .sensoryFeedback(.selection, trigger: open)
            ExpandReveal(open: open) {
                content()
                    .padding(.vertical, Space.xs)
                    .padding(.leading, RunLayout.processIndent)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(DS.rule.opacity(0.8)).frame(width: 1)
                            .padding(.vertical, Space.xs)
                            .padding(.leading, RunLayout.processLead / 2)
                            .accessibilityHidden(true)
                    }
            }
        }
    }
}

struct TurnProcessView: View {
    let items: [ChatItem]
    let maxBubbleWidth: CGFloat
    let spans: [String: TraceSpan]
    var initiallyOpen = false

    var body: some View {
        RunProcessRow(label: label, glyph: AppIcon.completed, initiallyOpen: initiallyOpen) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    ChatItemView(item: item, maxBubbleWidth: maxBubbleWidth, toolSpans: spans)
                        .padding(.vertical, item.text.isEmpty ? 0 : Space.xs)
                }
            }
        }
    }

    private var label: String {
        let calls = items.reduce(0) { $0 + $1.tools.count }
        let messages = items.filter { $0.role == .assistant && !$0.text.isEmpty }.count
        let thoughts = items.filter { !$0.reasoning.isEmpty }.count
        var parts = [String(localized: "Completed")]
        if calls > 0 { parts.append(String(localized: "\(calls) tool calls")) }
        if messages > 0 { parts.append(String(localized: "\(messages) messages")) }
        if calls == 0, messages == 0, thoughts > 0 { parts.append(String(localized: "\(thoughts) thoughts")) }
        return parts.joined(separator: " · ")
    }
}

struct ChatToolBatch: View {
    @Environment(\.designTheme) private var theme
    let tools: [ToolRow]
    let spans: [String: TraceSpan]
    let live: Bool
    @State private var open = false
    @State private var liveIDs: Set<String> = []

    var body: some View {
        let timed = tools.compactMap { spans[$0.id] }
        let summary = ToolSummary(timed)
        let leading = tools.min { $0.family.sortOrder < $1.family.sortOrder } ?? tools[0]
        let style = ToolPresenterRegistry.present(leading, args: leading.args, theme: theme).style
        VStack(alignment: .leading, spacing: 0) {
            RunProcessRow(label: summary.runLabel(fallbackCount: timed.count < tools.count ? tools.count : nil), glyph: style.glyph, style: style,
                          failed: summary.failed, didToggle: { open = $0 }) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tools) { ToolRowView(tool: $0, span: spans[$0.id]) }
                }
            }
            if live && !open {
                ForEach(tools.filter { liveIDs.contains($0.id) }) {
                    ToolRowView(tool: $0, span: spans[$0.id])
                }
            }
        }
        .onChange(of: tools.map(\.id), initial: true) { previous, next in
            let added = Set(next).subtracting(previous)
            let active = tools.filter { $0.result == nil }.map(\.id)
            if !added.isEmpty || liveIDs.isEmpty {
                liveIDs = added.union(active)
                if liveIDs.isEmpty, let last = next.last { liveIDs = [last] }
            }
        }
    }
}

extension ToolSummary {
    func runLabel(fallbackCount: Int? = nil) -> String {
        var parts: [String] = []
        if commands > 0 { parts.append(String(localized: "Ran \(commands) commands")) }
        if editedFiles > 0 { parts.append(String(localized: "Edited \(editedFiles) files")) }
        if readFiles > 0 { parts.append(String(localized: "Read \(readFiles) files")) }
        if searches > 0 { parts.append(String(localized: "Searched \(searches) times")) }
        if web > 0 { parts.append(String(localized: "\(web) web calls")) }
        if agents > 0 { parts.append(String(localized: "\(agents) agent calls")) }
        if todos > 0 { parts.append(String(localized: "Updated to-dos")) }
        if other > 0 { parts.append(String(localized: "\(other) other tools")) }
        return parts.isEmpty ? String(localized: "\(fallbackCount ?? total) tool calls") : parts.joined(separator: " · ")
    }
}

private extension ToolFamily {
    var sortOrder: Int { [Self.command, .edit, .read, .search, .web, .agent, .todo, .other].firstIndex(of: self) ?? 7 }
}
