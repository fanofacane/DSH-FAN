// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/lib/ui/chat/widgets/{turn_footnote,message_actions}.dart.
import DSHClient
import SwiftUI

struct TurnFootnote: View {
    let trace: TurnTrace
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    ForEach(Array(variants.enumerated()), id: \.offset) { _, value in
                        Text(verbatim: value).fixedSize(horizontal: true, vertical: false)
                    }
                    Text(verbatim: variants.last ?? "").lineLimit(1)
                }
                Glyph(glyph: AppIcon.disclosure, size: 16)
            }
            .font(.system(size: RunLayout.footnoteSize).monospacedDigit())
            .foregroundStyle(DS.inkFaint)
            .frame(minHeight: RunLayout.actionSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Trajectory: \(variants.first ?? "")"))
        .accessibilityIdentifier("turn-trajectory")
    }

    private var variants: [String] {
        let time = RunFormat.duration(trace.duration)
        let steps = trace.steps > 0 ? String(localized: "\(trace.steps) steps") : nil
        let cost = RunPricing.estimate(trace).map(RunFormat.cost)
        let tokens = trace.usage.total.map { RunFormat.tokens($0) + " tokens" } ?? String(localized: "Tokens not reported")
        return [[time, steps, cost, tokens], [time, steps, cost], [time, cost], [time]]
            .map { $0.compactMap { $0 }.joined(separator: " · ") }
    }
}

struct ReplyActions<MenuItems: View>: View {
    let text: String
    let trace: TurnTrace?
    let open: (TurnTrace) -> Void
    @ViewBuilder let menuItems: () -> MenuItems
    @State private var copied = false
    @State private var copyCount = 0

    var body: some View {
        HStack(spacing: 0) {
            Button {
                UIPasteboard.general.string = text
                copied = true
                copyCount += 1
            } label: {
                icon(copied ? AppIcon.done : AppIcon.copy)
            }
            .accessibilityLabel(Text(copied ? "Copied" : "Copy"))
            .sensoryFeedback(.impact(weight: .light), trigger: copyCount)
            .task(id: copyCount) {
                guard copied else { return }
                do { try await Task.sleep(for: .milliseconds(1400)) } catch { return }
                copied = false
            }
            ShareLink(item: text) { icon(AppIcon.share) }.accessibilityLabel(Text("Share"))
            Menu(content: menuItems) { icon(AppIcon.more) }.accessibilityLabel(Text("More"))
            Spacer(minLength: Space.xs)
            if let trace {
                TurnFootnote(trace: trace) { open(trace) }.layoutPriority(1)
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, -Space.sm)
    }

    private func icon(_ glyph: DshGlyph) -> some View {
        Glyph(glyph: glyph, size: 20)
            .foregroundStyle(DS.inkFaint)
            .frame(width: RunLayout.actionSize, height: RunLayout.actionSize)
            .contentShape(Rectangle())
    }
}
