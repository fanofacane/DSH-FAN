// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import Observation
import SwiftUI

struct CapabilitySettingsPage: View {
    @Environment(AppSession.self) private var chat
    @State private var sections: [EngineNamespace] = []
    @State private var error: String?
    var body: some View {
        SettingsPage(title: "Search, images and video") {
            SettingsGroup {
                ForEach(sections) { section in
                    NavigationLink { EngineFormPage(model: EngineFormModel(section), displayTitle: capabilityTitle(section.id)) } label: {
                        SettingsRow(title: LocalizedStringKey(capabilityTitle(section.id)), subtitle: nil)
                    }.buttonStyle(.plain)
                }
                if !sections.contains(where: { $0.id.contains("media") }), chat.connection.state == .ready, error == nil {
                    SettingsRow(title: "Images and video", subtitle: String(localized: "Install a media plugin on this host to configure generation.")) { EmptyView() }
                }
                if sections.isEmpty && chat.connection.state == .ready && error == nil {
                    SettingsRow(title: "These capabilities are not installed on this host.") { EmptyView() }
                }
            }
            if let error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger) }
        }
        .task(id: chat.connection.state) {
            guard chat.connection.state == .ready else { return }
            do {
                sections = try await chat.connection.settingsAPI.describe().filter {
                    ["web", "web-search-deepseek", "web-deepseek-api", "web-fetch-http", "dsh-media", "media"].contains($0.id)
                        || $0.id.contains("media")
                }
                error = nil
            } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
        }
    }
    private func capabilityTitle(_ ns: String) -> String {
        if ns.contains("media") { return String(localized: "Images and video") }
        if ns == "web" { return String(localized: "Search and fetch providers") }
        if ns == "web-deepseek-api" { return String(localized: "DeepSeek Search API") }
        if ns == "web-search-deepseek" { return String(localized: "DeepSeek Messages search") }
        return String(localized: "Web fetch")
    }
}

@MainActor @Observable final class EngineFormModel {
    var section: EngineNamespace
    var draft: [String: Any] // 引擎 schema 表单定义任意字段，保留其动态值。
    var changes: [[String]: Any] = [:]
    var error: String?
    var saving = false
    init(_ section: EngineNamespace) { self.section = section; draft = section.value }
    var schema: EngineSchema { EngineSchema(section.schema) }
    func value(_ path: [String]) -> Any? {
        path.reduce(draft as Any?) { current, key in
            if let map = current as? [String: Any] { return map[key] } // 引擎 schema 表单定义任意字段，保留其动态值。
            if let list = current as? [Any], let index = Int(key), list.indices.contains(index) { return list[index] }
            return nil
        }
    }
    func set(_ path: [String], _ value: Any) {
        guard !section.secretPaths.contains(where: { $0.count > path.count && $0.starts(with: path) }) else {
            error = "E_SETTINGS_HIDDEN_SECRET"; return
        }
        func replacing(_ current: Any?, _ rest: ArraySlice<String>) -> Any {
            guard let key = rest.first else { return value }
            if var list = current as? [Any], let index = Int(key), list.indices.contains(index) {
                list[index] = replacing(list[index], rest.dropFirst()); return list
            }
            var map = current as? [String: Any] ?? [:] // 引擎 schema 表单定义任意字段，保留其动态值。
            map[key] = replacing(map[key], rest.dropFirst()); return map
        }
        draft = replacing(draft, path[...]) as? [String: Any] ?? draft // 引擎 schema 表单定义任意字段，保留其动态值。
        if let ancestor = changes.keys.first(where: { path.starts(with: $0) }) {
            changes[ancestor] = self.value(ancestor) ?? NSNull()
        } else {
            for child in Array(changes.keys) where child.starts(with: path) { changes[child] = nil }
            changes[path] = value
        }
    }
    func save(_ chat: AppSession) async {
        saving = true; error = nil; defer { saving = false }
        do {
            let ops = changes.keys.sorted { $0.joined(separator: "/") < $1.joined(separator: "/") }.map { ["op": "set", "path": $0, "value": changes[$0]!] }
            let response = try await chat.connection.settingsAPI.mutate(ns: section.id, expectedRevision: section.revision, ops: ops, writable: section.writable)
            guard response.id == section.id else { throw DSHError("E_SETTINGS_RESPONSE") }
            section = response; draft = section.value; changes = [:]
        } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
    }
}

struct EngineFormPage: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    @State var model: EngineFormModel
    var displayTitle: String? = nil
    var path: [String] = []
    var node: [String: Any]? = nil // 引擎 schema 表单定义任意字段，保留其动态值。
    @State private var addKey = false
    @State private var key = ""
    @State private var editing: EngineFieldDestination?
    private var resolved: [String: Any] { model.schema.effective(node ?? model.schema.root) } // 引擎 schema 表单定义任意字段，保留其动态值。
    private var type: String { resolved["type"] as? String ?? "" }
    private var fields: [String: [String: Any]] { model.schema.fields(resolved) } // 引擎 schema 表单定义任意字段，保留其动态值。
    private var title: String { path.last.map(fieldTitle) ?? displayTitle ?? model.section.id }
    private var mediaPresets: [[String: Any]] { // 引擎 schema 表单定义任意字段，保留其动态值。
        let extra = (resolved["meta"] as? [String: Any])?["extra"] as? [String: Any] // 引擎 schema 表单定义任意字段，保留其动态值。
        // 远程主机可能仍装着上游 dsh-media（旧命名空间 dsh-go），新名优先、旧名兜底。
        let catalog = (extra?["dsh-fan/media/catalog"] ?? extra?["dsh-go/media/catalog"]) as? [String: Any]
        return catalog?["presets"] as? [[String: Any]] ?? [] // 引擎 schema 表单定义任意字段，保留其动态值。
    }
    var body: some View {
        SettingsPage(title: LocalizedStringKey(title)) {
            SettingsGroup {
                if type == "object" || type == "intersect" {
                    ForEach(fields.keys.sorted(), id: \.self) { key in
                        let child = fields[key] ?? [:]
                        if (child["meta"] as? [String: Any])?["hidden"] as? Bool != true { field(key, node: child) } // 引擎 schema 表单定义任意字段，保留其动态值。
                    }
                } else if type == "array" {
                    let list = model.value(path) as? [Any] ?? []
                    ForEach(list.indices, id: \.self) { index in
                        field(String(index), node: model.schema.resolve(resolved["inner"] ?? [:]))
                            .contextMenu { Button("Remove", role: .destructive) { remove(String(index)) } }
                    }
                } else if type == "dict" {
                    ForEach((model.value(path) as? [String: Any] ?? [:]).keys.sorted(), id: \.self) { key in // 引擎 schema 表单定义任意字段，保留其动态值。
                        field(key, node: model.schema.resolve(resolved["inner"] ?? [:]))
                            .contextMenu { Button("Remove", role: .destructive) { remove(key) } }
                    }
                } else { SettingsRow(title: "This setting format is not supported.") { EmptyView() } }
            }
            if !mediaPresets.isEmpty && type == "array" {
                Menu("Add service from catalog") {
                    ForEach(Array(mediaPresets.enumerated()), id: \.offset) { _, preset in
                        Button(presetLabel(preset)) { addPreset(preset) }
                    }
                }.foregroundStyle(theme.accent).padding(.bottom, 16)
            }
            if type == "array" || type == "dict" {
                MistButton(title: "Add item", kind: .secondary) {
                    if type == "dict" { key = ""; addKey = true }
                    else {
                        let inner = model.schema.resolve(resolved["inner"] ?? [:])
                        var list = model.value(path) as? [Any] ?? []
                        list.append(model.schema.defaultValue(inner)); model.set(path, list)
                    }
                }.disabled(!model.section.writable || model.saving).padding(.bottom, 16)
            }
            if let error = model.error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger).padding(.bottom, 12) }
            MistButton(title: "Save changes", busy: model.saving) { Task { await model.save(chat) } }
                .disabled(model.changes.isEmpty || !model.section.writable || model.saving)
            if !model.section.writable { Text("This host’s settings are read-only.").type(.bodySmall).foregroundStyle(DS.inkFaint) }
        }
        .sheet(item: $editing) { destination in
            EngineFieldEditor(model: model, path: destination.path, node: destination.node)
        }
        .alert("Add item", isPresented: $addKey) {
            TextField("Name", text: $key)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                var map = model.value(path) as? [String: Any] ?? [:] // 引擎 schema 表单定义任意字段，保留其动态值。
                map[key] = model.schema.defaultValue(model.schema.resolve(resolved["inner"] ?? [:]))
                model.set(path, map)
            }.disabled(key.isEmpty || (model.value(path) as? [String: Any])?[key] != nil) // 引擎 schema 表单定义任意字段，保留其动态值。
        }
    }
    private func presetLabel(_ preset: [String: Any]) -> String { // 引擎 schema 表单定义任意字段，保留其动态值。
        if Locale.preferredLanguages.first?.hasPrefix("zh") == false { return preset["labelEn"] as? String ?? preset["label"] as? String ?? "" }
        return preset["label"] as? String ?? preset["id"] as? String ?? ""
    }
    private func addPreset(_ preset: [String: Any]) { // 引擎 schema 表单定义任意字段，保留其动态值。
        var list = model.value(path) as? [[String: Any]] ?? [] // 引擎 schema 表单定义任意字段，保留其动态值。
        let stem = (preset["id"] as? String ?? "service").replacingOccurrences(of: "-", with: "_")
        var id = String(stem.prefix(24)), suffix = 1
        while list.contains(where: { $0["id"] as? String == id }) { suffix += 1; id = String(stem.prefix(24)) + "_" + String(suffix) }
        var item: [String: Any] = ["id": id, "label": presetLabel(preset), "enabled": false, // 引擎 schema 表单定义任意字段，保留其动态值。
                                   "models": (preset["models"] as? [String] ?? []).joined(separator: ","),
                                   "keyRef": "DSH_MEDIA_" + (preset["keyGroup"] as? String ?? id).uppercased().replacingOccurrences(of: "-", with: "_") + "_API_KEY"]
        for key in ["provider", "baseUrl", "profile", "responseFormat"] { item[key] = preset[key] ?? (key == "responseFormat" ? "" : nil) }
        list.append(item); model.set(path, list)
    }
    private func remove(_ key: String) {
        if type == "array", let index = Int(key), var list = model.value(path) as? [Any], list.indices.contains(index) {
            list.remove(at: index); model.set(path, list)
        } else if var map = model.value(path) as? [String: Any] { // 引擎 schema 表单定义任意字段，保留其动态值。
            map[key] = nil; model.set(path, map)
        }
    }
    @ViewBuilder private func field(_ key: String, node raw: [String: Any]) -> some View { // 引擎 schema 表单定义任意字段，保留其动态值。
        let child = model.schema.effective(raw), next = path + [key]
        let kind = child["type"] as? String ?? ""
        let meta = child["meta"] as? [String: Any] ?? [:] // 引擎 schema 表单定义任意字段，保留其动态值。
        let label = EngineSchema.localized(meta["title"]) ?? fieldTitle(key)
        let detail = EngineSchema.localized(meta["description"])
        if ["object", "intersect", "array", "dict"].contains(kind) {
            NavigationLink { EngineFormPage(model: model, path: next, node: child) } label: {
                SettingsRow(title: "", subtitle: detail, verbatim: label) { SettingsChevron() }
            }.buttonStyle(.plain)
        } else {
            Button { editing = EngineFieldDestination(path: next, node: child) } label: {
                SettingsRow(title: "", subtitle: detail, verbatim: label) {
                    Text(verbatim: meta["role"] as? String == "secret" ? "••••" : displayValue(model.value(next)))
                        .type(.bodySmall).foregroundStyle(DS.inkFaint).lineLimit(2)
                }
            }.buttonStyle(.plain).disabled(!model.section.writable || meta["disabled"] as? Bool == true || model.saving)
        }
    }
}

private struct EngineFieldDestination: Identifiable {
    var id: String { path.joined(separator: "/") }
    let path: [String]
    let node: [String: Any] // 引擎 schema 表单定义任意字段，保留其动态值。
}
private struct EngineFieldEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: EngineFormModel
    let path: [String]
    let node: [String: Any] // 引擎 schema 表单定义任意字段，保留其动态值。
    @State private var text = ""
    @State private var bool = false
    @State private var error = false
    @State private var showCredential = false
    private var kind: String { node["type"] as? String ?? "" }
    private var secret: Bool { (node["meta"] as? [String: Any])?["role"] as? String == "secret" } // 引擎 schema 表单定义任意字段，保留其动态值。
    private var credentialReference: String? {
        let parent = Array(path.dropLast())
        for key in ["credentialRef", "keyRef", "apiKeyEnv"] {
            if let ref = model.value(parent + [key]) as? String, !ref.isEmpty { return ref }
        }
        return nil
    }
    private var isCredentialReference: Bool {
        (node["meta"] as? [String: Any])?["role"] as? String == "credential-ref" || ["keyRef", "apiKeyEnv", "credentialRef"].contains(path.last ?? "") // 引擎 schema 表单定义任意字段，保留其动态值。
    }
    private var constants: [Any]? { model.schema.constants(node) }
    var body: some View {
        NavigationStack {
            SettingsPage(title: LocalizedStringKey(fieldTitle(path.last ?? "")), showsBack: false) {
                SettingsGroup {
                    if kind == "boolean" { Toggle("Enabled", isOn: $bool).padding(16) }
                    else if let constants {
                        Picker("Value", selection: $text) {
                            ForEach(Array(constants.enumerated()), id: \.offset) { index, value in
                                Text(verbatim: displayValue(value)).tag(String(index))
                            }
                        }.pickerStyle(.wheel)
                    } else if secret {
                        if credentialReference != nil {
                            Button("Configure referenced key") { showCredential = true }.padding(16)
                        } else { Text("Configure this secret using its engine plugin.").padding(16) }
                    } else if kind == "string" || kind == "number" {
                        TextField("Value", text: $text, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled().padding(16)
                            .keyboardType(kind == "number" ? .numbersAndPunctuation : .default)
                    } else { Text("This setting format is not supported.").padding(16) }
                }
                if error { Text("Enter a valid value.").type(.bodySmall).foregroundStyle(DS.danger) }
                if !secret { MistButton(title: "Apply to draft") {
                    let value: Any
                    if kind == "boolean" { value = bool }
                    else if let constants, let index = Int(text), constants.indices.contains(index) { value = constants[index] }
                    else if kind == "number" {
                        guard let number = Double(text), number.isFinite else { error = true; return }; value = number
                    } else { value = text }
                    model.set(path, value); text = ""; dismiss()
                }.disabled(!["boolean", "string", "number", "const", "union"].contains(kind)) }
                if isCredentialReference, !secret, !text.isEmpty {
                    MistButton(title: "Configure referenced key", kind: .secondary) { showCredential = true }.padding(.top, 12)
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onAppear {
            let value = model.value(path)
            bool = value as? Bool ?? false
            if let constants { text = String(constants.firstIndex { displayValue($0) == displayValue(value) } ?? 0) }
            else { text = secret ? "" : displayValue(value) }
        }
        .onDisappear { text = "" }
        .sheet(isPresented: $showCredential) { CredentialKeyEditor(reference: secret ? credentialReference ?? "" : text) }
    }
}

struct CredentialKeyEditor: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    @Environment(\.dismiss) private var dismiss
    let reference: String
    @State private var key = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            SettingsPage(title: "API key", showsBack: false) {
                Text(verbatim: reference).font(Mono.font(13, scale: theme.readingScale)).foregroundStyle(DS.inkMuted).padding(.bottom, 12)
                SecureField("API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled().padding(16).glass(.card)
                if let error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger) }
                MistButton(title: "Save", busy: busy) {
                    busy = true
                    Task {
                        do { try await chat.connection.credentialsAPI.set(ref: reference, value: key); key = ""; dismiss() }
                        catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
                        busy = false
                    }
                }.disabled(key.isEmpty || busy).padding(.top, 12)
            }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.onDisappear { key = "" }
    }
}

private func displayValue(_ value: Any?) -> String {
    guard let value, !(value is NSNull) else { return "" }
    if let text = value as? String { return text }
    return String(describing: value)
}
private func fieldTitle(_ key: String) -> String {
    switch key {
    case "apiKey": String(localized: "API key")
    case "keyRef", "apiKeyEnv": String(localized: "API key reference")
    case "baseURL", "baseUrl": String(localized: "API base URL")
    case "searchProvider": String(localized: "Search provider")
    case "fetchProvider": String(localized: "Fetch provider")
    case "maxUses", "count": String(localized: "Search limit")
    case "services": String(localized: "Services")
    case "defaults": String(localized: "Defaults")
    case "limits": String(localized: "Limits")
    case "enabled": String(localized: "Enabled")
    case "label", "name": String(localized: "Name")
    case "models": String(localized: "Model")
    case "budget": String(localized: "Cost guard")
    case "dailyCny": String(localized: "Daily budget (CNY)")
    case "unknownPriceHoldCny": String(localized: "Reserve for unknown prices (CNY)")
    case "credentials": String(localized: "Credentials")
    case "serviceId", "imageServiceId", "videoServiceId": String(localized: "Default service ID")
    case "modelId", "imageModelId", "videoModelId": String(localized: "Default model ID")
    case "profile": String(localized: "Protocol")
    case "responseFormat": String(localized: "Response format")
    case "provider": String(localized: "Provider ID")
    default: key
    }
}
