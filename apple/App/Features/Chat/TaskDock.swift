// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/lib/ui/chat/dock/{chat_dock,dock_stack,dock_pill,todo_bar,goal_bar}.dart.
import DSHClient
import SwiftUI

struct TaskDock: View {
    @Environment(\.designTheme) private var theme
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(AppSession.self) private var chat
    @AppStorage("chat.dockFolded") private var storedFolded = true
    var openTrace: (TurnTrace) -> Void
    var previewFolded: Bool?
    var previewTodoOpen = false
    @State private var foldOverride: Bool?
    @State private var front: Card?
    @State private var showGoal = false

    private enum Card: String, Identifiable {
        case todo, goal, activity
        var id: Self { self }
    }

    var body: some View {
        let todos = chat.control.projection.todos
        let goal = chat.control.projection.goal
        let activity = RunActivity.resolve(chat, theme: theme)
        let cards: [Card] = [todos.isEmpty ? nil : .todo, goal == nil ? nil : .goal, activity == nil ? nil : .activity].compactMap { $0 }
        let folded = cards.count > 1 && (foldOverride ?? previewFolded ?? storedFolded)
        VStack(spacing: RunLayout.dockGap) {
            if folded, let visible = cards.last {
                let front = front.flatMap { cards.contains($0) ? $0 : nil } ?? visible
                ZStack(alignment: .bottom) {
                    ForEach(Array(cards.filter { $0 != front }.enumerated().reversed()), id: \.element) { offset, _ in
                        let depth = CGFloat(offset + 1)
                        Capsule().fill(DS.surfaceHigh)
                            .overlay { Capsule().strokeBorder(DS.rule.opacity(0.6), lineWidth: 0.5) }
                            .frame(height: RunLayout.dockHeight)
                            .scaleEffect(x: 1 - RunLayout.dockShrink * depth, y: 1)
                            .offset(y: -RunLayout.dockPeek * depth)
                            .accessibilityHidden(true)
                    }
                    card(front, todos: todos, goal: goal, activity: activity, folded: true)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    Button { setFold(false) } label: {
                        Capsule().fill(.clear).contentShape(Capsule()).frame(height: RunLayout.dockHeight)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(cards.count) status bars stacked"))
                    .accessibilityHint(Text("Expand status bars"))
                    .accessibilityAction(named: Text("Next card")) { rotate(cards, from: front, by: -1) }
                    .accessibilityAction(named: Text("Previous card")) { rotate(cards, from: front, by: 1) }
                }
                .padding(.top, RunLayout.dockPeek * CGFloat(cards.count - 1))
                .simultaneousGesture(DragGesture(minimumDistance: 18).onEnded { value in
                    let distance = abs(value.translation.height) > RunLayout.dockSwipe ? value.translation.height : value.predictedEndTranslation.height
                    if abs(distance) > RunLayout.dockSwipe, abs(distance) > abs(value.translation.width) {
                        rotate(cards, from: front, by: distance > 0 ? -1 : 1)
                    }
                })
            } else {
                ForEach(cards) { kind in
                    HStack(alignment: .top, spacing: Space.sm) {
                        card(kind, todos: todos, goal: goal, activity: activity, folded: false)
                        if cards.count > 1 && kind == cards.first {
                            Button { setFold(true) } label: {
                                Glyph(glyph: AppIcon.foldTurns, size: 18)
                                    .foregroundStyle(DS.inkMuted)
                                    .frame(width: RunLayout.dockHeight, height: RunLayout.dockHeight)
                                    .glassCircle()
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Fold the status bars"))
                        }
                    }
                    .transition(.offset(y: RunLayout.dockHeight / 2).combined(with: .opacity))
                }
            }
            if let code = chat.control.error {
                Text("Request failed: \(code)").type(.bodySmall).foregroundStyle(DS.danger)
            }
        }
        .animation(reduceMotion ? nil : AppMotion.standard, value: cards)
        .animation(reduceMotion ? nil : AppMotion.standard, value: folded)
        .animation(reduceMotion ? nil : AppMotion.glide, value: front)
        .onChange(of: cards) { front = nil }
        .onChange(of: chat.transcript.currentSessionId) { front = nil }
        .sensoryFeedback(.selection, trigger: folded)
        .sensoryFeedback(.selection, trigger: front)
        .sheet(isPresented: $showGoal) {
            if let goal { GoalDockActions(goal: goal) }
        }
    }

    @ViewBuilder private func card(_ kind: Card, todos: [TodoItem], goal: GoalState?, activity: RunActivity?, folded: Bool) -> some View {
        switch kind {
        case .todo:
            TodoDockBar(todos: todos, running: chat.transcript.turnRunning, compact: folded, initiallyOpen: previewTodoOpen)
                .id(chat.transcript.currentSessionId)
        case .goal:
            if let goal { GoalDockBar(goal: goal) { showGoal = true } }
        case .activity:
            if let activity {
                let trace = chat.transcript.traceFold.running
                let progress = folded && !todos.isEmpty ? (todos.filter { $0.status == "completed" }.count, todos.count) : nil
                ActivityStrip(activity: activity, skew: chat.transcript.clockSkew ?? 0, rate: chat.transcript.tokenRate,
                              progress: progress, open: trace.map { trace in { openTrace(trace) } })
                    .id(chat.transcript.currentSessionId)
            }
        }
    }

    private func setFold(_ folded: Bool) {
        if previewFolded == nil { storedFolded = folded }
        else { foldOverride = folded }
        front = nil
    }

    private func rotate(_ cards: [Card], from card: Card, by step: Int) {
        guard let index = cards.firstIndex(of: card), !cards.isEmpty else { return }
        front = cards[(index + step + cards.count) % cards.count]
    }
}

struct DockProgress: View {
    let fraction: Double
    @Environment(\.designTheme) private var theme
    var body: some View {
        Capsule().fill(DS.capsuleTrack)
            .frame(width: 28, height: 3)
            .overlay(alignment: .leading) {
                Capsule().fill(fraction >= 1 ? DS.success : theme.accent).frame(width: 28 * fraction)
            }
            .accessibilityHidden(true)
    }
}

struct TodoDockBar: View {
    let todos: [TodoItem]
    let running: Bool
    var compact = false
    var initiallyOpen = false
    @State private var toggled: Bool?
    private var expanded: Bool { !compact && (toggled ?? initiallyOpen) }

    private var done: Int { todos.filter { $0.status == "completed" }.count }
    private var current: Int? {
        todos.firstIndex { $0.status == "in_progress" } ?? todos.firstIndex { $0.status != "completed" }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button { toggled = !expanded } label: {
                HStack(spacing: Space.md) {
                    Glyph(glyph: AppIcon.todo, size: 18).frame(width: RunLayout.dockGlyph)
                    HStack(spacing: Space.xs) {
                        Text(verbatim: "\(done)/\(todos.count)").type(.labelMedium).monospacedDigit().foregroundStyle(DS.ink)
                        Text(verbatim: "·  " + label).type(.bodySmall).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    DockProgress(fraction: Double(done) / Double(max(1, todos.count)))
                    Glyph(glyph: expanded ? AppIcon.expand : AppIcon.collapse, size: 18).frame(width: RunLayout.dockGlyph)
                }
                .padding(.horizontal, Space.sm)
                .frame(minHeight: RunLayout.dockHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(expanded ? "Expanded" : "Collapsed"))
            .sensoryFeedback(.selection, trigger: expanded)
            ExpandReveal(open: expanded) {
                ScrollViewReader { proxy in
                    ViewThatFits(in: .vertical) {
                        checklist
                        ScrollView { checklist }
                    }
                    .frame(maxHeight: RunLayout.todoListMax)
                    .onAppear { if let current { proxy.scrollTo(current, anchor: .center) } }
                }
            }
        }
        .foregroundStyle(DS.inkMuted)
        .glass(.chrome, radius: RunLayout.dockHeight / 2)
    }

    private var label: String {
        guard let current else { return String(localized: "All done") }
        let todo = todos[current]
        return running && todo.status == "in_progress"
            ? String(localized: "Working on: \(todo.content)") : String(localized: "Next: \(todo.content)")
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(Array(todos.enumerated()), id: \.offset) { index, todo in
                let completed = todo.status == "completed"
                HStack(alignment: .top, spacing: Space.sm) {
                    Glyph(glyph: completed ? AppIcon.completed : index == current ? DshGlyph.playCircle : .circle, size: 16)
                        .foregroundStyle(completed ? DS.success : DS.inkFaint)
                    Text(verbatim: todo.content).type(index == current ? .labelMedium : .bodySmall)
                        .foregroundStyle(completed ? DS.inkFaint : DS.ink)
                        .strikethrough(completed)
                    Spacer(minLength: 0)
                }
                .id(index)
            }
        }
        .padding([.horizontal, .bottom], Space.md)
    }
}

struct GoalDockBar: View {
    let goal: GoalState
    var busy = false
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: Space.sm) {
                Glyph(glyph: goal.phase == "blocked" ? AppIcon.error : AppIcon.goal, size: 18).frame(width: RunLayout.dockGlyph)
                Text("Goal").type(.labelMedium)
                Text(verbatim: goal.objective.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
                    .type(.bodySmall).lineLimit(1)
                Spacer(minLength: 0)
                if goal.phase == "blocked" { Text("Blocked").type(.labelMedium).foregroundStyle(DS.warn) }
                if goal.phase == "paused" { Text("Paused").type(.labelMedium).foregroundStyle(DS.inkFaint) }
                if busy { ProgressView().controlSize(.mini) }
                else { Glyph(glyph: AppIcon.more, size: 18).frame(width: RunLayout.dockGlyph) }
            }
            .foregroundStyle(DS.inkMuted)
            .padding(.horizontal, Space.sm)
            .frame(minHeight: RunLayout.dockHeight)
            .contentShape(Rectangle())
            .glassCapsule()
        }
        .buttonStyle(.plain)
    }
}

struct GoalDockActions: View {
    let goal: GoalState
    var previewClear = false
    @Environment(AppSession.self) private var chat
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmingClear = false
    @State private var changing = false
    @State private var objective = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack {
                    Text("Goal").type(.hero)
                    Spacer()
                    GlassIconButton(glyph: AppIcon.close, label: "Close") { dismiss() }
                }
                SheetGroup {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text(verbatim: goal.objective).type(.body)
                        HStack {
                            Text(LocalizedStringKey("Goal phase: " + goal.phase))
                            Text("Rounds: \(goal.rounds)/\(goal.maximum)")
                        }.type(.bodySmall).foregroundStyle(DS.inkFaint)
                        if let reason = goal.blockedReason {
                            Text(verbatim: reason).type(.bodySmall).foregroundStyle(DS.warn)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(Space.lg)
                }
                if previewClear || confirmingClear {
                    SheetGroup {
                        Text("Clear goal?").type(.titleMedium).padding(Space.md)
                        HStack(spacing: Space.lg) {
                            Button("Cancel") { confirmingClear = false }
                            Button("Clear goal", role: .destructive) { change(.clear) }
                        }.padding(.bottom, Space.md)
                    }
                } else {
                    SheetGroup {
                        action(goal.phase == "paused" ? "Resume goal" : "Pause goal") {
                            change(goal.phase == "paused" ? .resume : .pause)
                        }
                        action("Edit goal") { objective = goal.objective; editing = true }
                        action("Complete goal") { change(.complete) }
                        action("Clear goal", tone: .danger) { confirmingClear = true }
                    }
                    .disabled(changing)
                }
                if let error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger) }
            }
            .foregroundStyle(DS.ink)
            .padding(Space.xl)
        }
        .background(DS.surface)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .alert("Edit goal", isPresented: $editing) {
            TextField("Objective", text: $objective)
            Button("Cancel", role: .cancel) {}
            Button("Save") { change(.edit, objective: objective) }
                .disabled(objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func action(_ title: LocalizedStringKey, tone: TileTone = .ai, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { SettingsRow(tone: tone, title: title) }
            .buttonStyle(.plain)
    }

    private func change(_ operation: GoalOperation, objective: String? = nil) {
        guard !changing, chat.control.projection.goal?.id == goal.id else { return }
        changing = true
        error = nil
        Task {
            defer { changing = false }
            do {
                try await chat.control.changeGoal(operation, goal: goal, objective: objective)
                dismiss()
            } catch { self.error = appErrorCode(error) }
        }
    }
}
