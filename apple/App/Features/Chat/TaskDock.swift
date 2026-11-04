// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import SwiftUI

struct TaskDock: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    @State private var expanded = false
    @State private var editing = false
    @State private var objective = ""
    @State private var error: String?
    @State private var changing = false
    private var todos: [TodoItem] { chat.control.projection.todos }
    private var goal: GoalState? { chat.control.projection.goal }
    var body: some View {
        if !todos.isEmpty || goal != nil || chat.control.error != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let goal {
                    HStack {
                        Image(systemName: "target").foregroundStyle(theme.accent)
                        Text(verbatim: goal.objective).type(.bodyMedium).lineLimit(expanded ? nil : 1)
                        Spacer(minLength: 0)
                        Menu {
                            Button("Pause goal") { change(.pause, goal) }
                            Button("Resume goal") { change(.resume, goal) }
                            Button("Edit goal") { objective = goal.objective; editing = true }
                            Button("Complete goal") { change(.complete, goal) }
                            Button("Clear goal", role: .destructive) { change(.clear, goal) }
                        } label: { Image(systemName: "ellipsis.circle").frame(width: 32, height: 32) }
                        .disabled(changing)
                    }
                    HStack {
                        Text(LocalizedStringKey("Goal phase: " + goal.phase)).type(.bodySmall)
                        Text("Rounds: \(goal.rounds)/\(goal.maximum)").type(.bodySmall)
                    }.foregroundStyle(DS.inkFaint)
                    if let reason = goal.blockedReason { Text(verbatim: reason).type(.bodySmall).foregroundStyle(DS.warn) }
                }
                if !todos.isEmpty {
                    Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                        HStack {
                            Image(systemName: "checklist")
                            Text("Tasks: \(todos.filter { $0.status == "completed" }.count)/\(todos.count)")
                            Spacer()
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        }.type(.bodySmall)
                    }.buttonStyle(.plain)
                    if expanded {
                        ForEach(Array(todos.enumerated()), id: \.offset) { _, todo in
                            HStack(alignment: .top) {
                                Image(systemName: todo.status == "completed" ? "checkmark.circle.fill" :
                                        todo.status == "in_progress" ? "arrow.trianglehead.2.clockwise" : "circle")
                                Text(verbatim: todo.content).type(.bodySmall)
                            }
                        }
                    }
                }
                if let code = error ?? chat.control.error { Text("Request failed: \(code)").type(.bodySmall).foregroundStyle(DS.danger) }
            }
            .foregroundStyle(DS.ink).padding(12).glass(.card, radius: Radius.lg)
            .alert("Edit goal", isPresented: $editing) {
                TextField("Objective", text: $objective)
                Button("Cancel", role: .cancel) {}
                Button("Save") { if let goal { change(.edit, goal, objective: objective) } }
                    .disabled(objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    private func change(_ verb: GoalOperation, _ goal: GoalState, objective: String? = nil) {
        changing = true; error = nil
        Task {
            do { try await chat.control.changeGoal(verb, goal: goal, objective: objective) }
            catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
            changing = false
        }
    }
}
