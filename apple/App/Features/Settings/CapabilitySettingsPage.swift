// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/engine_settings/web_search_page.dart and app/lib/ui/settings/{media_settings_page,media/}.
import DSHClient
import SwiftUI

struct CapabilitySettingsPage: View {
    enum Kind { case all, search, media }
    var kind: Kind = .all
    @Environment(AppSession.self) private var chat
    @State private var loader = EngineSettingsLoad()
    @State private var webUpdate: EngineNamespace?
    @State private var saving = false
    @State private var error: String?
    @State private var retry = 0

    private var title: LocalizedStringKey {
        switch kind {
        case .all: "Capabilities"
        case .search: "Web search"
        case .media: "Images and video"
        }
    }
    private var web: EngineNamespace? { webUpdate ?? namespace("web") }
    private var canSwitch: Bool { web != nil && namespace("web-deepseek-api") != nil }
    private var usesAPI: Bool { canSwitch && web?.value["searchProvider"] as? String == "deepseek-search-api" }

    var body: some View {
        Group {
            if kind == .search, let section = namespace(usesAPI ? "web-deepseek-api" : "web-search-deepseek") {
                EngineFormPage(model: EngineFormModel(section, generation: loader.generation), displayTitle: title,
                               beforeFields: canSwitch ? AnyView(SettingsGroup { searchSwitch }) : nil)
                    .id("\(chat.connection.generation)-\(section.id)")
            } else if kind == .media, let section = mediaNamespace {
                EngineFormPage(model: EngineFormModel(section, generation: loader.generation), displayTitle: title)
                    .id("\(chat.connection.generation)-\(section.id)")
            } else {
                SettingsPage(title: title) {
                    if kind == .search && canSwitch { SettingsGroup { searchSwitch } }
                    let sections = fallbackSections
                    if !sections.isEmpty {
                        SettingsGroup {
                            ForEach(sections) { section in
                                SettingsLink(title: title(for: section.id)) {
                                    EngineFormPage(model: EngineFormModel(section, generation: loader.generation),
                                                   displayTitle: title(for: section.id))
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
        .task(id: "\(chat.connection.generation)-\(chat.connection.state == .ready)-\(retry)") {
            webUpdate = nil
            error = nil
            await loader.read(chat)
        }
    }

    private var searchSwitch: some View {
        SettingsToggleRow(title: "Use DeepSeek Search API",
                          subtitle: error.map { String(localized: "Request failed: \($0)") },
                          isOn: Binding(get: { usesAPI }, set: { value in Task { await changeProvider(value) } }))
            .disabled(saving || web?.writable != true)
    }

    private func namespace(_ name: String) -> EngineNamespace? {
        loader.current(in: chat).first { $0.id == name }
    }

    private var mediaNamespace: EngineNamespace? {
        loader.current(in: chat).first { mediaCatalog(in: $0) != nil } ?? namespace("media") ?? namespace("dsh-media")
    }

    private var fallbackSections: [EngineNamespace] {
        loader.current(in: chat).filter { section in
            let isWeb = section.id == "web" || section.id.hasPrefix("web-")
            let isMedia = section.id == mediaNamespace?.id
            return (kind != .media && isWeb) || (kind != .search && isMedia)
        }
    }

    private func title(for namespace: String) -> LocalizedStringKey {
        switch namespace {
        case "media", "dsh-media": "Images and video"
        case "web": "Search and fetch providers"
        case "web-deepseek-api": "DeepSeek Search API"
        case "web-search-deepseek": "DeepSeek Messages search"
        default: namespace == mediaNamespace?.id ? "Images and video" : "Web fetch"
        }
    }

    private func changeProvider(_ api: Bool) async {
        guard !saving, canSwitch, let web, web.writable, usesAPI != api,
              loader.generation == chat.connection.generation else { return }
        let generation = chat.connection.generation
        let targets = [("searchProvider", api ? "deepseek-search-api" : "deepseek-official"),
                       ("fetchProvider", api ? "deepseek-fetch-api" : "http")]
        let ops: [[String: Any]] = targets.map { key, value in
            if web.base?[key] as? String == value { return ["op": "unset", "path": [key]] }
            return ["op": "set", "path": [key], "value": value]
        }
        error = nil
        saving = true
        defer { saving = false }
        do {
            let response = try await chat.connection.settingsAPI.mutate(ns: web.id, expectedRevision: web.revision, ops: ops)
            guard generation == chat.connection.generation else { return }
            guard response.id == web.id else { throw DSHError("E_SETTINGS_RESPONSE") }
            webUpdate = response
        } catch {
            if generation == chat.connection.generation { self.error = appErrorCode(error) }
        }
    }
}
