// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/providers/new_chat_defaults_card.dart and app/lib/state/model_defaults_state.dart.
import DSHClient
import SwiftUI

struct NewChatDefaultsPage: View {
    @Environment(AppSession.self) private var chat
    @State var section: EngineNamespace
    let generation: Int
    let onSave: () -> Void
    @State private var selection: ModelOption?
    @State private var effort: String?
    @State private var remember = false
    @State private var saving = false
    @State private var error: String?

    private var models: [ModelOption] {
        #if DEBUG
        if DebugPageRegistry.usesFixture { return DebugProviderSettings.models }
        #endif
        return chat.connection.models
    }
    private var fields: [String: [String: Any]] { EngineSchema(section.schema).fields(EngineSchema(section.schema).root) }
    private var supportsRemember: Bool { fields["rememberLastSelection"]?["type"] as? String == "boolean" }
    private var canWrite: Bool {
        section.writable && generation == chat.connection.generation && chat.connection.state == .ready
            && ["provider", "model", "reasoningEffort"].allSatisfy { writable($0, type: "string") }
    }

    var body: some View {
        SettingsPage(title: "New chat defaults") {
            SettingsGroup(header: "Default model") {
                if models.isEmpty {
                    SettingsRow(title: "No models available") { EmptyView() }
                } else {
                    Picker("Default model", selection: $selection) {
                        Text("Choose a model").tag(nil as ModelOption?)
                        ForEach(models) { model in Text(model.name).tag(Optional(model)) }
                    }.padding(.horizontal, SettingsMetrics.inset).frame(minHeight: SettingsMetrics.row)
                    if let selection, !selection.efforts.isEmpty {
                        Picker("Thinking effort", selection: $effort) {
                            Text("Engine default").tag(nil as String?)
                            ForEach(selection.efforts) { effort in Text(effort.name).tag(Optional(effort.id)) }
                        }.padding(.horizontal, SettingsMetrics.inset).frame(minHeight: SettingsMetrics.row)
                    }
                }
                if supportsRemember {
                    SettingsToggleRow(title: "Remember the last model", isOn: $remember)
                        .disabled(!writable("rememberLastSelection", type: "boolean"))
                }
            }.disabled(!canWrite || saving)
            if let error { Text("Request failed: \(error)").settingsType(.bodySmall).foregroundStyle(DS.danger) }
            if !canWrite { Text("This host’s settings are read-only.").settingsType(.bodySmall).foregroundStyle(DS.inkFaint) }
            MistButton(title: "Save", busy: saving) { Task { await save() } }
                .disabled(!canWrite || saving || selection == nil)
        }
        .task {
            selection = models.first { $0.provider == section.value["provider"] as? String && $0.model == section.value["model"] as? String }
            remember = section.value["rememberLastSelection"] as? Bool == true
            effort = section.value["reasoningEffort"] as? String
        }
        .onChange(of: selection) { _, model in
            if let model, effort != nil && !model.efforts.contains(where: { $0.id == effort }) { effort = nil }
        }
    }

    private func writable(_ key: String, type: String) -> Bool {
        guard let node = fields[key], node["type"] as? String == type else { return false }
        return !EngineFieldRules(schema: EngineSchema(section.schema), node: node).locked
    }

    private func save() async {
        guard canWrite, !saving, let selection, models.contains(selection) else { return }
        if effort == nil, section.base?["reasoningEffort"] is String {
            error = "E_SETTINGS_INHERITED_EFFORT"
            return
        }
        let remember = remember
        let effort = effort
        var ops: [[String: Any]] = [
            ["op": "set", "path": ["provider"], "value": selection.provider],
            ["op": "set", "path": ["model"], "value": selection.model],
        ]
        if let effort { ops.append(["op": "set", "path": ["reasoningEffort"], "value": effort]) }
        else { ops.append(["op": "unset", "path": ["reasoningEffort"]]) }
        let writesMode = writable("rememberLastSelection", type: "boolean")
        if writesMode { ops.append(["op": "set", "path": ["rememberLastSelection"], "value": remember]) }
        saving = true; error = nil
        defer { saving = false }
        do {
            let api = try chat.connection.settingsAPI
            let response = try await api.mutate(ns: section.id, expectedRevision: section.revision, ops: ops)
            guard response.id == section.id else { throw DSHError("E_SETTINGS_RESPONSE") }
            guard generation == chat.connection.generation else { throw DSHError("E_SETTINGS_HOST_CHANGED") }
            section = response
            let confirmed = try await api.describe().first { $0.id == section.id }
            guard generation == chat.connection.generation else { throw DSHError("E_SETTINGS_HOST_CHANGED") }
            guard let confirmed else { throw DSHError("E_SETTINGS_RESPONSE") }
            section = confirmed
            chat.connection.updateNewChatDefault(from: confirmed)
            guard confirmed.value["provider"] as? String == selection.provider,
                  confirmed.value["model"] as? String == selection.model,
                  confirmed.value["reasoningEffort"] as? String == effort,
                  !writesMode || confirmed.value["rememberLastSelection"] as? Bool == remember else {
                throw DSHError("E_SETTINGS_UNCONFIRMED")
            }
            onSave()
        } catch { self.error = appErrorCode(error) }
    }
}
