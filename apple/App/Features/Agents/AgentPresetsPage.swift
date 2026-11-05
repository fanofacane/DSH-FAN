// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/features/agent_presets_page.dart.
import DSHClient
import SwiftUI

struct AgentPresetsPage: View {
    @Environment(AppSession.self) private var chat
    @State private var presets: [AgentPreset] = []
    @State private var defaults: EngineNamespace?
    @State private var error: String?
    @State private var loading = false
    @State private var retry = 0

    var body: some View {
        SettingsPage(title: "Agent presets") {
            if loading { ProgressView().frame(maxWidth: .infinity).padding(Space.lg) }
            SettingsGroup(header: "Available presets") {
                ForEach(presets, id: \.id) { preset in
                    NavigationLink {
                        AgentPresetPage(preset: preset, defaults: defaults, generation: chat.connection.generation,
                                        onChange: { retry += 1 })
                    } label: {
                        SettingsRow(glyph: AppIcon.profile, title: "", subtitle: preset.description,
                                    verbatim: preset.name ?? preset.id ?? "") {
                            if preset.isDefault { StatusChip(tone: .ok, label: "Default") }
                            else if chat.agents.selectedAgentPreset == preset.id { Glyph(glyph: .check, size: 16).foregroundStyle(DS.success) }
                            else { SettingsChevron() }
                        }
                    }.buttonStyle(SettingsPressStyle())
                }
                if presets.isEmpty && !loading && error == nil {
                    SettingsRow(title: chat.connection.state == .ready ? "No presets reported" : "Connect to a host to read its settings.") { EmptyView() }
                }
            }
            if let error {
                Text("Request failed: \(error)").settingsType(.bodySmall).foregroundStyle(DS.danger)
                MistButton(title: "Retry", kind: .secondary) { retry += 1 }
            }
        }
        .task(id: "\(chat.connection.generation)-\(chat.connection.state == .ready)-\(retry)") { await load() }
    }

    private func load() async {
        presets = []; defaults = nil; error = nil; loading = false
        #if DEBUG
        if DebugPageRegistry.usesFixture {
            presets = [
                AgentPreset(id: "default", name: String(localized: "Standard agent"),
                            description: String(localized: "General chat and tools."), isDefault: true),
                AgentPreset(id: "review", name: String(localized: "Review agent"),
                            description: String(localized: "Review and explain changes.")),
            ]
            return
        }
        #endif
        guard chat.connection.state == .ready else { return }
        let generation = chat.connection.generation
        loading = true
        defer { if generation == chat.connection.generation { loading = false } }
        do {
            let api = try chat.connection.agentAPI
            let settings = try chat.connection.settingsAPI
            let reported = try await api.list()
            guard generation == chat.connection.generation, !Task.isCancelled else { return }
            var seen: Set<String> = []
            presets = reported.filter { preset in
                guard let id = preset.id, !id.isEmpty else { return false }
                return seen.insert(id).inserted
            }
            let sections = try await settings.describe()
            guard generation == chat.connection.generation, !Task.isCancelled else { return }
            defaults = sections.first { $0.id == "agent-preset-registry" }
        } catch {
            if generation == chat.connection.generation, !Task.isCancelled { self.error = appErrorCode(error) }
        }
    }
}

struct AgentPresetPage: View {
    @Environment(AppSession.self) private var chat
    @Environment(\.dismiss) private var dismiss
    let preset: AgentPreset
    @State var defaults: EngineNamespace?
    let generation: Int
    let onChange: () -> Void
    @State private var content = ""
    @State private var error: String?
    @State private var selecting = false
    @State private var isDefault: Bool?
    private var canChoose: Bool {
        generation == chat.connection.generation && chat.connection.state == .ready
            && !chat.transcript.busy && !selecting && preset.broken == nil
    }

    var body: some View {
        SettingsPage(title: "Agent preset") {
            PageHero(title: Text(verbatim: preset.name ?? preset.id ?? ""),
                     subtitle: preset.description.map { Text(verbatim: $0) }) {
                SettingsIcon(glyph: AppIcon.profile, size: 52)
            } trailing: {
                if isDefault ?? preset.isDefault { StatusChip(tone: .ok, label: "Default") }
            }
            if let broken = preset.broken { Text(verbatim: broken).settingsType(.bodySmall).foregroundStyle(DS.danger) }
            SettingsGroup(header: "Configuration") {
                if !content.isEmpty { CodeBlockView(language: "yaml", code: content) }
            }
            if defaults?.writable == true && !(isDefault ?? preset.isDefault) {
                MistButton(title: "Make default", busy: selecting) { Task { await makeDefault() } }
                    .disabled(!canChoose).padding(.bottom, Space.md)
            }
            MistButton(title: "Start a chat with this preset", kind: .secondary, busy: selecting) {
                Task { await startChat() }
            }.disabled(!canChoose)
            if let error { Text("Request failed: \(error)").settingsType(.bodySmall).foregroundStyle(DS.danger) }
        }
        .task {
            #if DEBUG
            if DebugPageRegistry.usesFixture {
                content = "name: Example\nmode: standard"
                return
            }
            #endif
            guard let id = preset.id, generation == chat.connection.generation else { return }
            do {
                let document = try await chat.connection.agentAPI.read(agentPreset: id)
                guard generation == chat.connection.generation else { return }
                content = document.content ?? ""
            } catch { self.error = appErrorCode(error) }
        }
    }

    private func startChat() async {
        guard canChoose, let id = preset.id else { return }
        selecting = true; error = nil
        defer { selecting = false }
        do {
            try await chat.agents.chooseAgentPreset(id)
            onChange()
            dismiss()
        } catch { self.error = appErrorCode(error) }
    }

    private func makeDefault() async {
        guard canChoose, let id = preset.id, let defaults, defaults.writable else { return }
        selecting = true; error = nil
        defer { selecting = false }
        do {
            let settings = try chat.connection.settingsAPI
            let agents = try chat.connection.agentAPI
            let confirmed = try await settings.mutate(ns: defaults.id, expectedRevision: defaults.revision,
                                                      ops: [["op": "set", "path": ["selectedDefault"], "value": id]])
            guard generation == chat.connection.generation else { throw DSHError("E_SETTINGS_HOST_CHANGED") }
            guard confirmed.id == defaults.id else { throw DSHError("E_SETTINGS_RESPONSE") }
            self.defaults = confirmed
            let next = try await agents.list()
            guard generation == chat.connection.generation else { throw DSHError("E_SETTINGS_HOST_CHANGED") }
            onChange()
            guard next.contains(where: { $0.id == id && $0.isDefault }) else { throw DSHError("E_SETTINGS_UNCONFIRMED") }
            chat.agents.clearSelection()
            isDefault = true
        } catch { self.error = appErrorCode(error) }
    }
}
