// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/providers/{provider_form_page,provider_model_page}.dart.
import DSHClient
import SwiftUI

struct ProviderEditor: View {
    @Environment(AppSession.self) private var chat
    @Environment(\.dismiss) private var dismiss
    let provider: ConfigurableProvider?
    let sections: [EngineNamespace]
    var sourceGeneration: Int? = nil
    var onSave: () -> Void = {}
    @State private var route = ""
    @State private var name = ""
    @State private var endpoint = ""
    @State private var protocolName = "openai-completions"
    @State private var models = ""
    @State private var key = ""
    @State private var requiresKey = true
    @State private var configured = false
    @State private var writableKey = true
    @State private var busy = false
    @State private var error: String?
    @State private var original: [String: Any] = [:] // 引擎 schema 表单定义任意字段，保留其动态值。
    @State private var modelSpecs: [[String: Any]] = [] // 引擎 schema 表单定义任意字段，保留其动态值。
    @State private var section: EngineNamespace?
    @State private var removeKey = false
    @State private var generation: Int?
    @State private var showModelEditor = false
    @State private var editingModelID: String?
    @State private var discovered: [DiscoveredModel] = []
    @State private var selectedDiscoveries: Set<String> = []
    @State private var showDiscovery = false
    @State private var initialized = false
    @State private var created = false
    private var ns: String { provider == nil ? "llm-pi-ai" : (provider?.settingsNs ?? "") }
    private var currentHost: Bool { generation == chat.connection.generation && chat.connection.state == .ready }
    private var custom: Bool { provider == nil || ns == "llm-pi-ai" }
    private var path: [String] { provider?.settingsPath ?? ["providers", route] }
    private var keyRef: String {
        original["apiKeyEnv"] as? String ?? (route == "deepseek-api" ? DSHClient.deepSeekKeyRef : route.uppercased().replacingOccurrences(of: "-", with: "_") + "_API_KEY")
    }
    private var needsModels: Bool { provider == nil || provider?.declared == true || !(original["models"] as? [[String: Any]] ?? []).isEmpty }
    private var valid: Bool {
        guard route.range(of: "^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$", options: .regularExpression) != nil else { return false }
        if !custom { return !key.isEmpty && writableKey }
        if !needsModels && endpoint.isEmpty { return true }
        return URL(string: endpoint).map { ["http", "https"].contains($0.scheme ?? "") && $0.host != nil && $0.user == nil && $0.password == nil } == true && (!needsModels || !modelIDs.isEmpty)
    }
    private var modelIDs: [String] { Array(NSOrderedSet(array: models.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })) as? [String] ?? [] }
    var body: some View {
        SettingsPage(title: provider == nil ? "Add provider" : "Provider settings") {
            if provider != nil && ns.isEmpty {
                Text("Configuration is managed by this engine plugin.").settingsType(.bodyMedium).foregroundStyle(DS.inkMuted)
            }
            SettingsGroup(header: "Provider") {
                TextField("Provider ID", text: $route).disabled(provider != nil || created)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().padding(Space.lg)
                if custom {
                    TextField("Display name", text: $name).padding(Space.lg)
                    TextField("API base URL", text: $endpoint).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().keyboardType(.URL).padding(Space.lg)
                    Picker("Protocol", selection: $protocolName) {
                        if provider != nil { Text("Engine default").tag("catalog") }
                        ForEach(["openai-completions", "openai-responses", "anthropic-messages"], id: \.self) { Text(verbatim: $0).tag($0) }
                    }.padding(Space.md)
                    SettingsToggleRow(title: "Requires API key", isOn: $requiresKey)
                }
                if requiresKey {
                    SecureField("API key (leave blank to keep)", text: $key).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().padding(Space.lg).disabled(!writableKey || ns.isEmpty)
                    SettingsRow(title: configured ? "Key configured" : "No key yet") { EmptyView() }
                }
            }.disabled(busy)
            if custom { modelsGroup.disabled(busy) }
            if let error { Text("Request failed: \(error)").settingsType(.bodySmall).foregroundStyle(DS.danger).padding(.bottom, Space.md) }
            MistButton(title: "Save", busy: busy) { Task { await save() } }
                .disabled(busy || !valid || !currentHost || section?.writable == false || ns.isEmpty || (custom && section == nil))
            if configured && writableKey {
                MistButton(title: "Remove key", kind: .danger) { removeKey = true }
                    .disabled(busy || !currentHost).padding(.top, Space.md)
            }
        }
        .task { await load() }
        .onDisappear { key = "" }
        .sheet(isPresented: $showModelEditor) {
            ProviderModelEditor(original: modelSpecs.first { $0["id"] as? String == editingModelID }
                                ?? editingModelID.map { ["id": $0] }, reservedIDs: Set(modelIDs)) { model in
                guard let id = model["id"] as? String else { return }
                if !modelIDs.contains(id) { models = (modelIDs + [id]).joined(separator: "\n") }
                if let index = modelSpecs.firstIndex(where: { $0["id"] as? String == id }) { modelSpecs[index] = model }
                else { modelSpecs.append(model) }
            }
        }
        .sheet(isPresented: $showDiscovery) { discoverySheet }
        .confirmationDialog("Remove this provider key?", isPresented: $removeKey, titleVisibility: .visible) {
            Button("Remove key", role: .destructive) { Task { await deleteKey() } }
        }
    }

    private var modelsGroup: some View {
        SettingsGroup(header: "Models") {
            ForEach(modelIDs, id: \.self) { id in
                Button { editingModelID = id; showModelEditor = true } label: {
                    let spec = modelSpecs.first { $0["id"] as? String == id }
                    SettingsRow(glyph: AppIcon.providers, title: "", subtitle: spec?["name"] as? String,
                                verbatim: id) { SettingsChevron() }
                }.buttonStyle(SettingsPressStyle())
                .contextMenu {
                    Button("Remove", role: .destructive) {
                        models = modelIDs.filter { $0 != id }.joined(separator: "\n")
                        modelSpecs.removeAll { $0["id"] as? String == id }
                    }
                }
            }
            Button { editingModelID = nil; showModelEditor = true } label: {
                SettingsRow(glyph: AppIcon.add, title: "Add model")
            }.buttonStyle(SettingsPressStyle())
            Button { Task { await discover() } } label: {
                SettingsRow(glyph: AppIcon.retry, title: "Fetch models") { if busy { ProgressView() } }
            }.buttonStyle(SettingsPressStyle()).disabled(!currentHost || endpoint.isEmpty)
        }
    }

    private var discoverySheet: some View {
        SettingsSheet(title: "Discovered models", locked: true) {
            ScrollView {
                SheetGroup {
                    ForEach(discovered.compactMap(\.id), id: \.self) { id in
                        let hasModel = modelIDs.contains(id)
                        SettingsChoiceRow(title: id, selected: hasModel || selectedDiscoveries.contains(id)) {
                            if !selectedDiscoveries.insert(id).inserted { selectedDiscoveries.remove(id) }
                        }.disabled(hasModel)
                    }
                }
            }
            MistButton(title: "Add selected models") {
                let added = discovered.filter { $0.id.map(selectedDiscoveries.contains) == true }
                modelSpecs += added.map(\.settingsSpec)
                models = (modelIDs + added.compactMap(\.id)).joined(separator: "\n")
                showDiscovery = false
            }.disabled(selectedDiscoveries.isEmpty)
        }.presentationDetents([.medium, .large])
    }

    private func deleteKey() async {
        guard currentHost, !busy else { return }
        let generation = chat.connection.generation
        busy = true; error = nil
        defer { busy = false }
        do {
            try await chat.connection.credentialsAPI.unset(ref: keyRef)
            guard generation == chat.connection.generation else { throw DSHError("E_SETTINGS_HOST_CHANGED") }
            configured = false
            try await chat.connection.reloadModels()
            onSave()
        } catch { self.error = appErrorCode(error) }
    }

    private func load() async {
        guard !initialized else { return }
        initialized = true
        generation = sourceGeneration ?? chat.connection.generation
        route = provider?.provider ?? ""
        name = provider?.displayName ?? ""
        section = sections.first { $0.id == ns }
        if provider != nil {
            var current: Any = section?.value ?? [:]
            for component in path { current = (current as? [String: Any])?[component] ?? [:] } // 引擎 schema 表单定义任意字段，保留其动态值。
            original = current as? [String: Any] ?? [:] // 引擎 schema 表单定义任意字段，保留其动态值。
        }
        endpoint = original["baseURL"] as? String ?? provider?.defaultBaseURL ?? ""
        protocolName = original["api"] as? String ?? (provider == nil ? "openai-completions" : "catalog")
        modelSpecs = original["models"] as? [[String: Any]] ?? [] // 引擎 schema 表单定义任意字段，保留其动态值。
        models = modelSpecs.compactMap { $0["id"] as? String }.joined(separator: "\n")
        if provider != nil { requiresKey = original["apiKeyEnv"] != nil || !custom || modelSpecs.isEmpty }
        #if DEBUG
        if DebugPageRegistry.usesFixture {
            switch DebugPageRegistry.argument("-dsh-screen-fixture") {
            case "errors": route = "example"; name = "Example"; endpoint = "gw.example.com"; error = "E_PROVIDER_URL"
            case "picker":
                discovered = DebugProviderSettings.models.map { DiscoveredModel(id: $0.model, name: $0.name) }
                selectedDiscoveries = ["example/model"]
                showDiscovery = true
            default: break
            }
            configured = DebugPageRegistry.argument("-dsh-screen-fixture") == "ready"
            return
        }
        #endif
        if !route.isEmpty && !ns.isEmpty && currentHost {
            do {
                let states = try await chat.connection.credentialsAPI.describe(refs: [keyRef])
                guard currentHost else { return }
                configured = states[keyRef]?.configured == true
                writableKey = states[keyRef]?.writable == true
            } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
        }
    }
    private func discover() async {
        guard currentHost, !busy else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            var request = ModelDiscoveryRequest()
            if !endpoint.isEmpty { request.baseURL = endpoint }
            if protocolName != "catalog" { request.api = protocolName }
            if !key.isEmpty { request.apiKey = key }
            else if provider != nil { request.provider = route }
            let found = try await chat.connection.providerAPI.discoverModels(settingsNs: ns, request: request)
            guard currentHost else { throw DSHError("E_SETTINGS_HOST_CHANGED") }
            guard !found.isEmpty else { throw DSHError("E_NO_MODELS") }
            var seen: Set<String> = []
            discovered = found.filter { model in
                guard let id = model.id, !id.isEmpty else { return false }
                return seen.insert(id).inserted
            }
            guard !discovered.isEmpty else { throw DSHError("E_NO_MODELS") }
            selectedDiscoveries = []
            showDiscovery = true
        } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
    }
    private func save() async {
        guard currentHost, !busy, valid, !ns.isEmpty else { return }
        busy = true; error = nil; defer { busy = false }
        let credential = key
        do {
            if custom {
                guard let section else { throw DSHError("E_PROVIDER_ADAPTER_UNAVAILABLE") }
                if provider == nil, !created, (section.value["providers"] as? [String: Any])?[route] != nil { throw DSHError("E_PROVIDER_EXISTS") } // 引擎 schema 表单定义任意字段，保留其动态值。
                let specs = modelIDs.map { id in modelSpecs.first { $0["id"] as? String == id } ?? ["id": id] }
                var fields: [String: Any] = ["displayName": name] // 引擎 schema 表单定义任意字段，保留其动态值。
                if !endpoint.isEmpty { fields["baseURL"] = endpoint }
                if protocolName != "catalog" { fields["api"] = protocolName }
                if !specs.isEmpty { fields["models"] = specs }
                var ops: [[String: Any]] = fields.keys.sorted().map { ["op": "set", "path": path + [$0], "value": fields[$0]!] } // 引擎 schema 表单定义任意字段，保留其动态值。
                ops.append(requiresKey ? ["op": "set", "path": path + ["apiKeyEnv"], "value": keyRef] : ["op": "unset", "path": path + ["apiKeyEnv"]])
                let response = try await chat.connection.settingsAPI.mutate(ns: ns, expectedRevision: section.revision, ops: ops, writable: section.writable)
                guard currentHost else { throw DSHError("E_SETTINGS_HOST_CHANGED") }
                guard response.id == ns else { throw DSHError("E_SETTINGS_RESPONSE") }
                self.section = response
                created = true
            }
            if !credential.isEmpty && requiresKey {
                try await chat.connection.credentialsAPI.set(ref: keyRef, value: credential)
                guard currentHost else { throw DSHError("E_SETTINGS_HOST_CHANGED") }
                key = ""
                configured = true
            }
            try await chat.connection.reloadModels()
            guard currentHost else { throw DSHError("E_SETTINGS_HOST_CHANGED") }
            onSave()
            dismiss()
        } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
    }
}
