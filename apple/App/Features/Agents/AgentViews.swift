// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import SwiftUI

struct SubagentDock: View {
    @Environment(AppSession.self) private var chat
    @State private var expanded = false
    @State private var selected: SubagentRoute?
    private var children: [SubagentRoute] {
        guard let parent = chat.transcript.currentSessionId else { return [] }
        return chat.control.projection.subagents(parent: parent)
    }
    var body: some View {
        if !children.isEmpty {
            DisclosureGroup("Subtasks", isExpanded: $expanded) {
                ForEach(children) { child in
                    Button { selected = child } label: {
                        HStack {
                            Image(systemName: "person.crop.square")
                            Text(verbatim: child.label).lineLimit(2)
                            Spacer()
                            if chat.control.state.values[child.id]?.hasActiveSubagentTiming == true { ProgressView().controlSize(.mini) }
                            else { Image(systemName: "chevron.right") }
                        }.type(.bodySmall).foregroundStyle(DS.inkMuted).padding(.vertical, 6)
                    }.buttonStyle(.plain).disabled(!child.canOpen)
                }
            }.type(.bodySmall).foregroundStyle(DS.ink).padding(12).glass(.card, radius: Radius.lg)
            .sheet(item: $selected) { route in NavigationStack { SubagentPage(route: route) } }
        }
    }
}

struct SubagentPage: View {
    @Environment(AppSession.self) private var chat
    let route: SubagentRoute
    @State private var messages: [String] = []
    @State private var streaming = ""
    @State private var input = ""
    @State private var error: String?
    @State private var sending = false
    @State private var reload = 0
    @State private var truncated = false
    var body: some View {
        SettingsPage(title: "Subtask") {
            Text(verbatim: route.label).type(.titleMedium).foregroundStyle(DS.ink).padding(.bottom, 12)
            if truncated { Text("Showing recent subtask history.").type(.bodySmall).foregroundStyle(DS.inkFaint) }
            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                Text(verbatim: message).type(.bodyMedium).foregroundStyle(DS.ink).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12).glass(.card, radius: Radius.md).padding(.bottom, 8)
            }
            if !streaming.isEmpty { Text(verbatim: streaming).type(.bodyMedium).foregroundStyle(DS.inkMuted).padding(.bottom, 12) }
            if let error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger) }
            if route.canPrompt {
                TextField("Message the subagent…", text: $input, axis: .vertical).type(.body).padding(12).glass(.card)
                MistButton(title: "Send", busy: sending) {
                    let text = input; sending = true
                    Task {
                        do { try await chat.agents.promptChild(route, text: text); input = ""; error = nil }
                        catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
                        sending = false
                    }
                }.disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending).padding(.top, 12)
                MistButton(title: "Interrupt subtask", kind: .secondary) {
                    Task { do { try await chat.agents.interruptChild(route) } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" } }
                }.padding(.top, 12)
            } else { Text("This subtask is read-only.").type(.bodySmall).foregroundStyle(DS.inkFaint) }
            if error != nil { MistButton(title: "Retry", kind: .secondary) { reload += 1 }.padding(.top, 12) }
        }
        .task(id: reload) {
            messages = []; streaming = ""; error = nil
            do {
                for try await event in try await chat.agents.childEvents(route) {
                    guard !Task.isCancelled else { return }
                    switch event {
                    case .snapshot(let records, let more): messages = []; streaming = ""; truncated = more; for record in records { apply(record) }
                    case .event(let record): apply(record)
                    case .textDelta(let text): streaming += text
                    case .modelFailure(let code): error = code
                    default: break
                    }
                }
            } catch { if !Task.isCancelled { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" } }
        }
    }
    private func apply(_ record: LogEvent) {
        switch record {
        case .userMessage(_, let message): if message.sourceKind != "runtime-context" && !message.text.isEmpty { messages.append(message.text) }
        case .assistantMessage(_, _, _, let message, _): streaming = ""; if !message.text.isEmpty { messages.append(message.text) }
        case .toolResult(_, _, let text, let failed, _): if failed { error = "E_SUBAGENT_TOOL" }; if !text.isEmpty { messages.append(String(text.prefix(4000))) }
        default: break
        }
    }
}

struct AgentPresetsPage: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    @State private var presets: [AgentPreset] = []
    @State private var error: String?
    var body: some View {
        SettingsPage(title: "Agent presets") {
            SettingsGroup {
                ForEach(Array(presets.enumerated()), id: \.offset) { _, preset in
                    NavigationLink { AgentPresetPage(preset: preset) } label: {
                        SettingsRow(title: "", subtitle: preset.description,
                                    verbatim: preset.name ?? preset.id ?? "") {
                            if chat.agents.selectedAgentPreset == preset.id { Image(systemName: "checkmark").foregroundStyle(theme.accent) }
                            else { SettingsChevron() }
                        }
                    }.buttonStyle(.plain)
                }
            }
            if let error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger) }
        }.task(id: chat.connection.state) {
            guard chat.connection.state == .ready else { return }
            do {
                presets = try await chat.connection.agentAPI.list()
            } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
        }
    }
}
private struct AgentPresetPage: View {
    @Environment(AppSession.self) private var chat
    @Environment(\.dismiss) private var dismiss
    let preset: AgentPreset
    @State private var content = ""
    @State private var error: String?
    @State private var selecting = false
    var body: some View {
        SettingsPage(title: "Agent preset") {
            Text(verbatim: preset.name ?? preset.id ?? "").type(.titleMedium).foregroundStyle(DS.ink).padding(.bottom, 12)
            if let broken = preset.broken { Text(verbatim: broken).type(.bodySmall).foregroundStyle(DS.danger) }
            CodeBlockView(language: "yaml", code: content).padding(.bottom, 16)
            MistButton(title: "Use for new chats", busy: selecting) {
                selecting = true
                Task {
                    do { try await chat.agents.chooseAgentPreset(preset.id ?? ""); dismiss() }
                    catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
                    selecting = false
                }
            }.disabled(chat.transcript.busy || selecting || preset.broken != nil)
            if let error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger) }
        }.task {
            do {
                content = try await chat.connection.agentAPI.read(agentPreset: preset.id ?? "").content ?? ""
            } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
        }
    }
}
