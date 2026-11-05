// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/engine_settings/{engine_settings_hub,runtime_settings_pages,subagent_settings_page,general_settings_page,web_search_page}.dart.
import DSHClient
import SwiftUI

enum EngineSettingsPageID: String, CaseIterable {
    case subagent, agentLoop = "agent-loop", shell, general = "engine-general"

    var title: LocalizedStringKey {
        switch self {
        case .subagent: "Subagents"
        case .agentLoop: "Agent loop"
        case .shell: "Command execution"
        case .general: "Web interface settings"
        }
    }

    var glyph: DshGlyph {
        switch self {
        case .subagent: .usersThree
        case .agentLoop: .arrowsClockwise
        case .shell: AppIcon.terminal
        case .general: AppIcon.swap
        }
    }

    func namespaces(in sections: [EngineNamespace]) -> [EngineNamespace] {
        let names: [String]
        switch self {
        case .subagent: names = ["subagent", "subagent-model-selection-settings"]
        case .agentLoop: names = ["agent-loop"]
        case .shell: names = sections.contains { $0.id == "bash-sandbox" } ? ["bash-sandbox"] : ["pwsh-sandbox"]
        case .general: names = ["ui-settings", "ui-chat", "ui-conversation", "session-log-deepseek"]
        }
        return names.compactMap { name in sections.first { $0.id == name } }
    }

    func summary(in sections: [EngineNamespace]) -> String? {
        guard let section = namespaces(in: sections).first else { return nil }
        switch self {
        case .subagent:
            return (section.value["maxDepth"] as? Int).map { String(localized: "\($0) levels") }
        case .agentLoop:
            return (section.value["maxParallelToolCalls"] as? Int)?.formatted()
        case .shell:
            return (section.value["timeoutMs"] as? NSNumber).map { engineNumberLabel($0.doubleValue, key: "timeoutMs") }
        case .general:
            return nil
        }
    }
}

@MainActor @Observable final class EngineSettingsLoad {
    private var sections: [EngineNamespace] = []
    private(set) var generation: Int?

    func current(in chat: AppSession) -> [EngineNamespace] {
        generation == chat.connection.generation ? sections : []
    }
    private(set) var loading = false
    private(set) var error: String?

    func read(_ chat: AppSession) async {
        sections = []
        let generation = chat.connection.generation
        self.generation = generation
        error = nil
        loading = false
        #if DEBUG
        if DebugPageRegistry.usesFixture {
            sections = DebugEngineSettings.sections
            return
        }
        #endif
        guard chat.connection.state == .ready else { return }
        loading = true
        defer { if chat.connection.generation == generation { loading = false } }
        do {
            let next = try await chat.connection.settingsAPI.describe()
            if !Task.isCancelled, generation == chat.connection.generation { sections = next }
        } catch {
            if !Task.isCancelled, generation == chat.connection.generation { self.error = appErrorCode(error) }
        }
    }
}

struct EngineParametersPage: View {
    @Environment(AppSession.self) private var chat
    @Environment(HostStore.self) private var hosts
    @State private var loader = EngineSettingsLoad()
    @State private var retry = 0

    var body: some View {
        SettingsPage(title: "Engine parameters", subtitle: hosts.activeHost.map { LocalizedStringKey($0.name) }) {
            SettingsGroup(header: "Runtime") {
                ForEach([EngineSettingsPageID.subagent, .agentLoop, .shell], id: \.self) { page in
                    SettingsLink(glyph: page.glyph, title: page.title, value: page.summary(in: loader.current(in: chat))) {
                        EngineNamespacePage(id: page)
                    }
                }
            }
            if !EngineSettingsPageID.general.namespaces(in: loader.current(in: chat)).isEmpty {
                SettingsGroup(header: "Interface") {
                    SettingsLink(glyph: EngineSettingsPageID.general.glyph, title: EngineSettingsPageID.general.title) {
                        EngineNamespacePage(id: .general)
                    }
                }
            }
            if let error = loader.error {
                Text("Request failed: \(error)").settingsType(.bodySmall).foregroundStyle(DS.danger)
                MistButton(title: "Retry", kind: .secondary) { retry += 1 }
            }
        }
        .task(id: "\(chat.connection.generation)-\(chat.connection.state == .ready)-\(retry)") { await loader.read(chat) }
    }
}

struct EngineNamespacePage: View {
    let id: EngineSettingsPageID
    @Environment(AppSession.self) private var chat
    @State private var loader = EngineSettingsLoad()
    @State private var retry = 0

    var body: some View {
        let selected = id.namespaces(in: loader.current(in: chat))
        Group {
            if id == .subagent, let limits = selected.first(where: { $0.id == "subagent" }) {
                EngineFormPage(model: EngineFormModel(limits, generation: loader.generation), displayTitle: id.title,
                               afterFields: subagentModels(in: selected))
                    .id("\(chat.connection.generation)-\(limits.id)")
            } else if let first = selected.first, selected.count == 1 {
                EngineFormPage(model: EngineFormModel(first, generation: loader.generation),
                               displayTitle: id.title)
                    .id("\(chat.connection.generation)-\(first.id)")
            } else {
                SettingsPage(title: id.title) {
                    if !selected.isEmpty {
                        SettingsGroup {
                            ForEach(selected) { section in
                                SettingsLink(title: namespaceTitle(section.id)) {
                                    EngineFormPage(model: EngineFormModel(section, generation: loader.generation),
                                                   displayTitle: namespaceTitle(section.id))
                                }
                            }
                        }
                    } else if let error = loader.error {
                        Text("Request failed: \(error)").settingsType(.bodySmall).foregroundStyle(DS.danger)
                        MistButton(title: "Retry", kind: .secondary) { retry += 1 }
                    } else if loader.loading {
                        ProgressView().frame(maxWidth: .infinity).padding(Space.lg)
                    } else {
                        Text(chat.connection.state == .ready ? "No editable parameters reported by this host." : "Connect to a host to read its settings.")
                            .settingsType(.bodyMedium).foregroundStyle(DS.inkMuted).padding(Space.sm)
                    }
                }
            }
        }
        .task(id: "\(chat.connection.generation)-\(chat.connection.state == .ready)-\(retry)") { await loader.read(chat) }
    }

    private func subagentModels(in sections: [EngineNamespace]) -> AnyView? {
        guard let section = sections.first(where: { $0.id == "subagent-model-selection-settings" }) else { return nil }
        return AnyView(SubagentModelsSection(model: EngineFormModel(section, generation: loader.generation)))
    }

    private func namespaceTitle(_ namespace: String) -> LocalizedStringKey {
        switch namespace {
        case "ui-settings": "Web display"
        case "ui-chat": "Web chat"
        case "ui-conversation": "Web message sending"
        case "session-log-deepseek": "Upload chat logs to DeepSeek"
        case "subagent-model-selection-settings": "Subagent models"
        default: LocalizedStringKey(namespace)
        }
    }

}
