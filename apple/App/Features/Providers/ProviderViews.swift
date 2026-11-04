// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import SwiftUI

struct ProviderSettingsPage: View {
    @Environment(AppSession.self) private var chat
    @State private var providers: [ConfigurableProvider] = []
    @State private var namespaces: [EngineNamespace] = []
    @State private var error: String?
    @State private var adding = false
    var body: some View {
        SettingsPage(title: "Model providers") {
            MistButton(title: "Add provider") { adding = true }.padding(.bottom, 16)
            SettingsGroup {
                ForEach(Array(providers.enumerated()), id: \.offset) { index, provider in
                    if index > 0 { RowDivider() }
                    NavigationLink {
                        if provider.provider == "deepseek-account" { DeepSeekAccountPage() }
                        else { ProviderEditor(provider: provider, sections: namespaces) }
                    } label: {
                        SettingsRow(title: "", subtitle: provider.error,
                                    verbatim: provider.displayName ?? provider.provider ?? "") { SettingsChevron() }
                    }.buttonStyle(.plain)
                }
            }
            if let error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger) }
            MistButton(title: "Refresh", kind: .secondary) { Task { await load() } }.padding(.top, 12)
        }
        .task(id: chat.connection.state) { if chat.connection.state == .ready { await load() } }
        .navigationDestination(isPresented: $adding) { ProviderEditor(provider: nil, sections: namespaces) }
    }
    private func load() async {
        error = nil
        do {
            providers = try await chat.connection.providerAPI.listConfigurableProviders()
            namespaces = try await chat.connection.settingsAPI.describe()
            // Registered routes without a configurable profile still expose their
            // model names; their configuration belongs to their own engine plugin.
            let registered = try await chat.connection.providerAPI.listProviders()
            for provider in registered {
                guard let id = provider.id, !providers.contains(where: { $0.provider == id }) else { continue }
                providers.append(ConfigurableProvider(provider: id, displayName: provider.name ?? id))
            }
        } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
    }
}

struct ProviderEditor: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    @Environment(\.dismiss) private var dismiss
    let provider: ConfigurableProvider?
    let sections: [EngineNamespace]
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
    private var ns: String { provider?.settingsNs ?? "llm-pi-ai" }
    private var custom: Bool { provider == nil || ns == "llm-pi-ai" }
    private var path: [String] { provider?.settingsPath ?? ["providers", route] }
    private var keyRef: String {
        original["apiKeyEnv"] as? String ?? (route == "deepseek-api" ? DSHClient.deepSeekKeyRef : route.uppercased().replacingOccurrences(of: "-", with: "_") + "_API_KEY")
    }
    private var needsModels: Bool { provider == nil || provider?.declared == true || !modelSpecs.isEmpty }
    private var valid: Bool {
        guard route.range(of: "^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$", options: .regularExpression) != nil else { return false }
        if !custom { return !key.isEmpty }
        if !needsModels && endpoint.isEmpty { return true }
        return URL(string: endpoint).map { ["http", "https"].contains($0.scheme ?? "") && $0.host != nil && $0.user == nil && $0.password == nil } == true && (!needsModels || !modelIDs.isEmpty)
    }
    private var modelIDs: [String] { Array(NSOrderedSet(array: models.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })) as? [String] ?? [] }
    var body: some View {
        SettingsPage(title: "Provider settings") {
            if provider != nil && ns.isEmpty {
                Text("Configuration is managed by this engine plugin.").type(.bodyMedium).foregroundStyle(DS.inkMuted)
            }
            SettingsGroup {
                TextField("Provider ID", text: $route).disabled(provider != nil).textInputAutocapitalization(.never).autocorrectionDisabled().padding(16)
                if custom {
                    RowDivider(); TextField("Display name", text: $name).padding(16)
                    RowDivider(); TextField("API base URL", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).padding(16)
                    RowDivider()
                    Picker("Protocol", selection: $protocolName) {
                        if provider != nil { Text("Engine default").tag("catalog") }
                        ForEach(["openai-completions", "openai-responses", "anthropic-messages"], id: \.self) { Text(verbatim: $0).tag($0) }
                    }.padding(12)
                    SettingsToggleRow(title: "Requires API key", isOn: $requiresKey)
                }
                if requiresKey {
                    RowDivider()
                    SecureField("API key (leave blank to keep)", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled().padding(16).disabled(!writableKey)
                    SettingsRow(title: configured ? "Key configured" : "No key yet") { EmptyView() }
                }
            }
            if custom {
                SettingsGroup(header: "Models (one ID per line)") {
                    TextEditor(text: $models).font(Mono.font(14, scale: theme.readingScale)).frame(minHeight: 130).scrollContentBackground(.hidden).padding(10)
                }
                MistButton(title: "Fetch models", kind: .secondary, busy: busy) { Task { await discover() } }
                    .disabled(busy || endpoint.isEmpty).padding(.bottom, 12)
            }
            if let error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger).padding(.bottom, 12) }
            MistButton(title: "Save", busy: busy) { Task { await save() } }.disabled(busy || !valid || (section?.writable == false) || (provider != nil && ns.isEmpty))
            if configured && writableKey {
                MistButton(title: "Remove key", kind: .danger) { removeKey = true }.padding(.top, 12)
            }
        }
        .task { await load() }
        .onDisappear { key = "" }
        .confirmationDialog("Remove this provider key?", isPresented: $removeKey, titleVisibility: .visible) {
            Button("Remove key", role: .destructive) {
                Task {
                    do {
                        try await chat.connection.credentialsAPI.unset(ref: keyRef); configured = false
                        try await chat.connection.reloadModels()
                    } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
                }
            }
        }
    }
    private func load() async {
        guard route.isEmpty else { return }
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
        if !route.isEmpty {
            do {
                let states = try await chat.connection.credentialsAPI.describe(refs: [keyRef])
                configured = states[keyRef]?.configured == true
                writableKey = states[keyRef]?.writable == true
            } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
        }
    }
    private func discover() async {
        busy = true; error = nil; defer { busy = false }
        do {
            var request = ModelDiscoveryRequest()
            if !endpoint.isEmpty { request.baseURL = endpoint }
            if protocolName != "catalog" { request.api = protocolName }
            if !key.isEmpty { request.apiKey = key }
            else if provider != nil { request.provider = route }
            let found = try await chat.connection.providerAPI.discoverModels(settingsNs: ns, request: request)
            guard !found.isEmpty else { throw DSHError("E_NO_MODELS") }
            modelSpecs = found.map(\.settingsSpec)
            models = modelSpecs.compactMap { $0["id"] as? String }.joined(separator: "\n")
        } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
    }
    private func save() async {
        busy = true; error = nil; defer { busy = false }
        do {
            if custom {
                guard let section else { throw DSHError("E_PROVIDER_ADAPTER_UNAVAILABLE") }
                if provider == nil, (section.value["providers"] as? [String: Any])?[route] != nil { throw DSHError("E_PROVIDER_EXISTS") } // 引擎 schema 表单定义任意字段，保留其动态值。
                let specs = modelIDs.map { id in modelSpecs.first { $0["id"] as? String == id } ?? ["id": id] }
                var fields: [String: Any] = ["displayName": name] // 引擎 schema 表单定义任意字段，保留其动态值。
                if !endpoint.isEmpty { fields["baseURL"] = endpoint }
                if protocolName != "catalog" { fields["api"] = protocolName }
                if !specs.isEmpty { fields["models"] = specs }
                var ops: [[String: Any]] = fields.keys.sorted().map { ["op": "set", "path": path + [$0], "value": fields[$0]!] } // 引擎 schema 表单定义任意字段，保留其动态值。
                ops.append(requiresKey ? ["op": "set", "path": path + ["apiKeyEnv"], "value": keyRef] : ["op": "unset", "path": path + ["apiKeyEnv"]])
                let response = try await chat.connection.settingsAPI.mutate(ns: ns, expectedRevision: section.revision, ops: ops, writable: section.writable)
                self.section = response
            }
            if !key.isEmpty && requiresKey { try await chat.connection.credentialsAPI.set(ref: keyRef, value: key); key = "" }
            try await chat.connection.reloadModels()
            dismiss()
        } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
    }
}
