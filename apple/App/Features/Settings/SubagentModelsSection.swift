// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/engine_settings/subagent_settings_page.dart.
import DSHClient
import SwiftUI

struct SubagentModelsSection: View {
    struct Route: Hashable {
        let provider: String
        let model: String
        var json: [String: String] { ["provider": provider, "model": model] }
    }

    @Environment(AppSession.self) private var chat
    @State var model: EngineFormModel
    @State private var waitingForModel = false
    @State private var note: String?
    private var enabled: Bool { model.value(["enabled"]) as? Bool == true }
    private var allowed: [Route] {
        (model.value(["allowedModels"]) as? [[String: Any]] ?? []).compactMap { row in
            guard let provider = row["provider"] as? String, let id = row["model"] as? String else { return nil }
            return Route(provider: provider, model: id)
        }
    }
    private var models: [ModelOption] {
        #if DEBUG
        if DebugPageRegistry.usesFixture { return DebugProviderSettings.models }
        #endif
        return chat.connection.models
    }
    private var canEdit: Bool {
        let fields = model.schema.fields(model.schema.root)
        return model.section.writable && !model.saving && model.generation == chat.connection.generation
            && ["enabled", "allowedModels"].allSatisfy { key in
                guard let node = fields[key] else { return false }
                return !EngineFieldRules(schema: model.schema, node: node).locked
            }
    }

    private var footer: LocalizedStringKey? {
        if let note { return LocalizedStringKey(note) }
        return waitingForModel ? "Choose the first allowed model to enable selection." : nil
    }

    var body: some View {
        SettingsGroup(header: "Subagent models", footer: footer) {
            SettingsToggleRow(title: "Allow subagents to choose a model", isOn: Binding(
                get: { enabled || waitingForModel }, set: toggle
            )).disabled(!canEdit)
        }
        if enabled || waitingForModel {
            let grouped = Dictionary(grouping: models, by: \.provider)
            ForEach(grouped.keys.sorted(), id: \.self) { provider in
                SettingsGroup(header: LocalizedStringKey(provider)) {
                    ForEach(grouped[provider] ?? []) { model in
                        let route = Route(provider: provider, model: model.model)
                        SettingsChoiceRow(title: model.name, selected: allowed.contains(route)) { pick(route) }
                            .disabled(!canEdit)
                    }
                }
            }
            let known = Set(models.map { Route(provider: $0.provider, model: $0.model) })
            let unavailable = Array(Set(allowed).subtracting(known)).sorted { ($0.provider, $0.model) < ($1.provider, $1.model) }
            if !unavailable.isEmpty {
                SettingsGroup(header: "Saved but unavailable") {
                    ForEach(unavailable, id: \.self) { route in
                        SettingsChoiceRow(title: route.model, subtitle: route.provider, selected: true) { pick(route) }
                            .disabled(!canEdit)
                    }
                }
            } else if models.isEmpty {
                SettingsGroup {
                    SettingsLink(title: "Connect a model provider") { ProviderSettingsPage() }
                }
            }
        }
    }

    private func toggle(_ on: Bool) {
        guard canEdit else { return }
        note = nil
        waitingForModel = on && allowed.isEmpty
        if !waitingForModel, on != enabled { save(enabled: on, allowed: nil) }
    }

    private func pick(_ route: Route) {
        guard canEdit else { return }
        note = nil
        let picked = allowed.contains(route)
        if picked && enabled && Set(allowed).count == 1 {
            note = String(localized: "Keep at least one model while selection is enabled.")
            return
        }
        let next = picked ? allowed.filter { $0 != route } : allowed + [route]
        save(enabled: waitingForModel ? true : nil, allowed: next)
    }

    private func save(enabled: Bool?, allowed: [Route]?) {
        if let allowed { model.set(["allowedModels"], allowed.map(\.json)) }
        if let enabled { model.set(["enabled"], enabled) }
        Task {
            await model.save(chat)
            if let code = model.error {
                note = String(localized: "Request failed: \(code)")
                model.discardEdits()
            } else { waitingForModel = false }
        }
    }
}
