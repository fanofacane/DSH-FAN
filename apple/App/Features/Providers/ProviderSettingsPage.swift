// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/providers/{providers_page,provider_detail_page,provider_widgets}.dart.
import DSHClient
import SwiftUI

struct ProviderSettingsPage: View {
    @Environment(AppSession.self) private var chat
    @Environment(HostStore.self) private var hosts
    @State private var providers: [ConfigurableProvider] = []
    @State private var namespaces: [EngineNamespace] = []
    @State private var error: String?
    @State private var loading = false
    @State private var reload = 0
    @State private var loadGeneration: Int?

    var body: some View {
        SettingsPage(title: "Model providers", subtitle: hosts.activeHost.map { LocalizedStringKey($0.name) }) {
            SettingsGroup(header: "New chats") {
                if let section = namespaces.first(where: { $0.id == "agent-default-model" }) {
                    let model = section.value["model"] as? String
                    SettingsLink(glyph: AppIcon.providers, title: "Default model", value: model) {
                        NewChatDefaultsPage(section: section, generation: loadGeneration ?? -1) { reload += 1 }
                    }
                } else {
                    SettingsLink(glyph: AppIcon.providers, title: "Chat model") { ModelSettingsPage() }
                }
            }
            SettingsGroup(header: "Official") {
                if hosts.isRemote {
                    if let provider = providers.first(where: { $0.provider == "deepseek-api" }) {
                        SettingsLink(glyph: AppIcon.providers, title: "DeepSeek",
                                     subtitle: String(localized: "Configuration belongs to the selected host.")) {
                            ProviderDetailPage(provider: provider, namespaces: namespaces,
                                               sourceGeneration: loadGeneration, onSave: { reload += 1 })
                        }
                    } else {
                        SettingsRow(glyph: AppIcon.providers, title: "DeepSeek",
                                    subtitle: String(localized: "Configuration belongs to the selected host.")) { EmptyView() }
                    }
                } else {
                    SettingsLink(glyph: AppIcon.providers, title: "DeepSeek",
                                 subtitle: chat.connection.keyConfigured ? String(localized: "Key configured")
                                                                         : String(localized: "Sign in or use an API key")) {
                        DeepSeekAccountPage()
                    }
                }
            }
            SettingsGroup(header: "Custom providers") {
                ForEach(providers.filter { !["deepseek-account", "deepseek-api"].contains($0.provider ?? "") },
                        id: \.provider) { provider in
                    NavigationLink {
                        ProviderDetailPage(provider: provider, namespaces: namespaces,
                                           sourceGeneration: loadGeneration, onSave: { reload += 1 })
                    } label: {
                        SettingsRow(title: "", subtitle: provider.error ?? provider.defaultBaseURL,
                                    verbatim: provider.displayName ?? provider.provider ?? "") { SettingsChevron() }
                    }.buttonStyle(SettingsPressStyle())
                }
                if namespaces.contains(where: { $0.id == "llm-pi-ai" && $0.writable }) {
                    SettingsLink(glyph: AppIcon.add, title: "Add provider") {
                        ProviderEditor(provider: nil, sections: namespaces, sourceGeneration: loadGeneration, onSave: { reload += 1 })
                    }
                }
                if !loading && providers.isEmpty && error == nil && chat.connection.state != .ready {
                    SettingsRow(title: "Connect to a host to read its settings.") { EmptyView() }
                }
            }
            if loading { ProgressView().frame(maxWidth: .infinity).padding(Space.lg) }
            if let error { Text("Request failed: \(error)").settingsType(.bodySmall).foregroundStyle(DS.danger) }
            MistButton(title: "Refresh", kind: .secondary) { reload += 1 }
                .disabled(loading || chat.connection.state != .ready)
        }
        .task(id: "\(chat.connection.generation)-\(chat.connection.state == .ready)-\(reload)") { await load() }
    }

    private func load() async {
        providers = []
        namespaces = []
        loadGeneration = chat.connection.generation
        error = nil
        loading = false
        #if DEBUG
        if DebugPageRegistry.usesFixture {
            providers = DebugProviderSettings.providers
            namespaces = DebugProviderSettings.sections
            return
        }
        #endif
        guard chat.connection.state == .ready else { return }
        let generation = chat.connection.generation
        loading = true
        defer { if generation == chat.connection.generation { loading = false } }
        do {
            let providerAPI = try chat.connection.providerAPI
            let settingsAPI = try chat.connection.settingsAPI
            let configurable = try await providerAPI.listConfigurableProviders()
            guard generation == chat.connection.generation, !Task.isCancelled else { return }
            var seen: Set<String> = []
            providers = configurable.filter { item in
                guard let id = item.provider, !id.isEmpty else { return false }
                return seen.insert(id).inserted
            }
            let registered = try await providerAPI.listProviders()
            guard generation == chat.connection.generation, !Task.isCancelled else { return }
            for provider in registered {
                guard let id = provider.id, !id.isEmpty, seen.insert(id).inserted else { continue }
                providers.append(ConfigurableProvider(provider: id, displayName: provider.name ?? id))
            }
            let reported = try await settingsAPI.describe()
            guard generation == chat.connection.generation, !Task.isCancelled else { return }
            namespaces = reported
        } catch {
            if generation == chat.connection.generation, !Task.isCancelled { self.error = appErrorCode(error) }
        }
    }
}

struct ProviderDetailPage: View {
    @Environment(AppSession.self) private var chat
    @Environment(\.dismiss) private var dismiss
    let provider: ConfigurableProvider
    @State var namespaces: [EngineNamespace]
    var sourceGeneration: Int? = nil
    let onSave: () -> Void
    @State private var configured: Bool?
    @State private var error: String?
    @State private var loading = false
    @State private var reload = 0
    @State private var generation: Int?
    @State private var confirmRemove = false
    @State private var removing = false

    private var route: String { provider.provider ?? "" }
    private var path: [String] { provider.settingsPath ?? ["providers", route] }
    private var section: EngineNamespace? { namespaces.first { $0.id == provider.settingsNs } }
    private var canRemove: Bool {
        guard let section else { return false }
        return section.id == "llm-pi-ai" && section.writable && section.base != nil
            && engineValue(path, in: section.base) == nil && engineValue(path, in: section.user) != nil
            && generation == chat.connection.generation
    }
    private var settings: [String: Any] {
        engineValue(path, in: section?.value) as? [String: Any] ?? [:]
    }
    private var modelIDs: [String] {
        if let list = settings["models"] as? [[String: Any]] {
            return list.compactMap { $0["id"] as? String }
        }
        return chat.connection.models.filter { $0.provider == route }.map(\.model)
    }
    private var credential: String? {
        settings["apiKeyEnv"] as? String
    }

    var body: some View {
        let title = provider.displayName ?? route
        SettingsPage(title: LocalizedStringKey(title)) {
            PageHero(title: Text(verbatim: title), subtitle: Text(verbatim: route)) {
                SettingsIcon(glyph: AppIcon.providers, tone: .ai, size: 52)
            } trailing: {
                if configured != nil { StatusDot(tone: configured == true ? .ok : .idle) }
            }
            SettingsGroup(header: "Connection") {
                if let endpoint = settings["baseURL"] as? String ?? provider.defaultBaseURL {
                    SettingsRow(title: "API base URL", subtitle: endpoint) { EmptyView() }
                }
                if let protocolName = settings["api"] as? String { InfoRow(label: "Protocol", value: protocolName) }
                if credential != nil {
                    InfoRow(label: "API key", value: configured.map { String(localized: $0 ? "Configured" : "Not set") }
                            ?? String(localized: "Unknown"))
                }
                if provider.settingsNs?.isEmpty == false {
                    SettingsLink(glyph: AppIcon.configure, title: "Edit provider") {
                        ProviderEditor(provider: provider, sections: namespaces, sourceGeneration: generation, onSave: refresh)
                    }.disabled(generation != chat.connection.generation)
                }
            }
            SettingsGroup(header: "Models") {
                if modelIDs.isEmpty { SettingsRow(title: "No models available") { EmptyView() } }
                ForEach(Array(modelIDs.enumerated()), id: \.offset) { _, id in
                    SettingsRow(glyph: AppIcon.providers, title: "", verbatim: id) { EmptyView() }
                }
            }
            if canRemove {
                MistButton(title: "Remove provider", kind: .danger, busy: removing) { confirmRemove = true }
                    .disabled(removing)
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
            if let error { Text("Request failed: \(error)").settingsType(.bodySmall).foregroundStyle(DS.danger) }
        }
        .task(id: reload) { await load() }
        .confirmationDialog("Remove this provider?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove provider", role: .destructive) { Task { await remove() } }
        } message: {
            Text("New chats won’t be able to select this channel. Its credential remains available to other routes.")
        }
    }

    private func remove() async {
        guard canRemove, let section, !removing else { return }
        removing = true; error = nil
        defer { removing = false }
        do {
            let response = try await chat.connection.settingsAPI.mutate(
                ns: section.id, expectedRevision: section.revision, ops: [["op": "unset", "path": path]])
            guard generation == chat.connection.generation else { throw DSHError("E_SETTINGS_HOST_CHANGED") }
            guard response.id == section.id, engineValue(path, in: response.value) == nil else {
                throw DSHError("E_SETTINGS_UNCONFIRMED")
            }
            onSave()
            try await chat.connection.reloadModels()
            dismiss()
        } catch { self.error = appErrorCode(error) }
    }

    private func refresh() { reload += 1; onSave() }

    private func load() async {
        if generation == nil { generation = sourceGeneration ?? chat.connection.generation }
        guard generation == chat.connection.generation else { return }
        #if DEBUG
        if DebugPageRegistry.usesFixture {
            configured = DebugPageRegistry.argument("-dsh-screen-fixture") != "missing-key"
            return
        }
        #endif
        guard chat.connection.state == .ready else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            if reload > 0 {
                let next = try await chat.connection.settingsAPI.describe()
                guard generation == chat.connection.generation, !Task.isCancelled else { return }
                namespaces = next
            }
            if let credential {
                let status = try await chat.connection.credentialsAPI.describe(refs: [credential])
                guard generation == chat.connection.generation, !Task.isCancelled else { return }
                configured = status[credential]?.configured
            } else { configured = nil }
        } catch {
            if generation == chat.connection.generation, !Task.isCancelled { self.error = appErrorCode(error) }
        }
    }
}
