// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/engine_settings/{engine_settings_page,schema_form,field_row}.dart and ui/settings/media/.
import DSHClient
import Observation
import SwiftUI

@MainActor @Observable final class EngineFormModel {
    var section: EngineNamespace
    var draft: [String: Any] // 引擎 schema 表单定义任意字段，保留其动态值。
    private(set) var changes: [[String]: Any] = [:]
    private(set) var resets: Set<[String]> = []
    var error: String?
    private(set) var saving = false
    let generation: Int?

    init(_ section: EngineNamespace, generation: Int? = nil) {
        self.section = section
        self.generation = generation
        draft = section.value
    }

    var hasEdits: Bool { !changes.isEmpty || !resets.isEmpty }
    var schema: EngineSchema { EngineSchema(section.schema) }
    func value(_ path: [String]) -> Any? { engineValue(path, in: draft) }
    func modified(_ path: [String]) -> Bool { engineValue(path, in: section.user) != nil }

    func containsSecret(_ path: [String]) -> Bool {
        section.secretFields.contains { $0.starts(with: path) || path.starts(with: $0) }
    }

    func set(_ path: [String], _ value: Any) {
        guard !saving, section.writable, !path.isEmpty else { return }
        guard !containsSecret(path) else {
            error = "E_SETTINGS_HIDDEN_SECRET"; return
        }
        if engineValueEqual(self.value(path), value) { return }
        draft = replacing(draft, path[...], with: value) as? [String: Any] ?? draft
        resets = Set(resets.filter { !$0.starts(with: path) })
        if let ancestor = changes.keys.first(where: { path.starts(with: $0) }) {
            changes[ancestor] = self.value(ancestor) ?? NSNull()
        } else {
            for child in Array(changes.keys) where child.starts(with: path) { changes[child] = nil }
            let hasReset = resets.contains { path.starts(with: $0) }
            changes[path] = !hasReset && engineValueEqual(engineValue(path, in: section.value), value) ? nil : value
        }
    }
    func restore(_ path: [String]) {
        guard !saving, section.writable, !containsSecret(path), modified(path) else { return }
        draft = replacing(draft, path[...], with: engineValue(path, in: section.base)) as? [String: Any] ?? draft
        if let ancestor = changes.keys.first(where: { $0 != path && path.starts(with: $0) }) {
            changes[ancestor] = value(ancestor)
        } else {
            for key in Array(changes.keys) where key.starts(with: path) { changes[key] = nil }
            if !resets.contains(where: { path.starts(with: $0) }) {
                resets = Set(resets.filter { !$0.starts(with: path) })
                resets.insert(path)
            }
        }
    }

    private func replacing(_ current: Any?, _ path: ArraySlice<String>, with value: Any?) -> Any? {
        guard let key = path.first else { return value }
        if var list = current as? [Any], let index = Int(key), list.indices.contains(index) {
            list[index] = replacing(list[index], path.dropFirst(), with: value) ?? NSNull()
            return list
        }
        var map = current as? [String: Any] ?? [:]
        map[key] = replacing(map[key], path.dropFirst(), with: value)
        return map
    }

    func discardEdits() {
        guard !saving else { return }
        draft = section.value
        changes = [:]
        resets = []
    }

    private func rules(at path: [String]) -> EngineFieldRules? {
        var node = schema.effective(schema.root)
        for key in path {
            let rules = EngineFieldRules(schema: schema, node: node)
            if rules.locked || rules.hidden || rules.secret { return nil }
            if rules.collection && rules.type != "tuple" { node = rules.inner }
            else if let field = schema.fields(node)[key] { node = field }
            else { return nil }
        }
        let rules = EngineFieldRules(schema: schema, node: node)
        return rules.locked || rules.hidden || rules.secret ? nil : rules
    }

    func save(_ chat: AppSession) async {
        guard !saving, hasEdits, section.writable else { return }
        guard changes.allSatisfy({ path, value in
            guard let rules = rules(at: path) else { return false }
            return rules.valid(value)
        }) else { error = "E_SETTINGS_INVALID_DRAFT"; return }
        let generation = chat.connection.generation
        guard self.generation == nil || self.generation == generation else { error = "E_SETTINGS_HOST_CHANGED"; return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            let writes: [[String: Any]] = changes.keys.sorted { $0.lexicographicallyPrecedes($1) }.compactMap { path in
                changes[path].map { ["op": "set", "path": path, "value": $0] }
            }
            let unsets: [[String: Any]] = resets.sorted { $0.lexicographicallyPrecedes($1) }.map { ["op": "unset", "path": $0] }
            let response = try await chat.connection.settingsAPI.mutate(ns: section.id, expectedRevision: section.revision,
                                                                         ops: unsets + writes, writable: section.writable)
            guard generation == chat.connection.generation else { throw DSHError("E_SETTINGS_HOST_CHANGED") }
            guard response.id == section.id else { throw DSHError("E_SETTINGS_RESPONSE") }
            section = response
            saving = false
            discardEdits()
        } catch { self.error = appErrorCode(error) }
    }
}

struct EngineFormPage: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    @State var model: EngineFormModel
    var displayTitle: LocalizedStringKey? = nil
    var path: [String] = []
    var node: [String: Any]? = nil // 引擎 schema 表单定义任意字段，保留其动态值。
    var beforeFields: AnyView? = nil
    var afterFields: AnyView? = nil
    var inheritedLock = false
    @State private var addKey = false
    @State private var key = ""
    @State private var editing: EngineFieldDestination?
    private var resolved: [String: Any] { model.schema.effective(node ?? model.schema.root) } // 引擎 schema 表单定义任意字段，保留其动态值。
    private var type: String { resolved["type"] as? String ?? "" }
    private var fields: [String: [String: Any]] { model.schema.fields(resolved) } // 引擎 schema 表单定义任意字段，保留其动态值。
    private var title: LocalizedStringKey {
        if let key = path.last { return LocalizedStringKey(fieldTitle(key)) }
        return displayTitle ?? LocalizedStringKey(model.section.id)
    }
    @State private var showDocumentation = false
    @State private var expanded: Set<String> = []
    private var orderedKeys: [String] {
        let known: [String]
        switch model.section.id {
        case "bash-sandbox", "pwsh-sandbox": known = ["timeoutMs", "maxOutputBytes", "maxTimeoutMs", "maxSpillBytes", "graceMs"]
        case "subagent": known = ["maxDepth", "maxActiveSubagents", "maxActive"]
        case "web-search-deepseek", "web-deepseek-api": return ["apiKey", "baseURL", "maxUses", "count"].filter { fields[$0] != nil }
        default: known = mediaCatalog(in: model.section) != nil || ["media", "dsh-media"].contains(model.section.id)
            ? ["defaults", "services", "limits"] : []
        }
        return known.filter { fields[$0] != nil } + fields.keys.filter { !known.contains($0) }.sorted()
    }
    private var readOnly: Bool { inheritedLock || !model.section.writable }
    private var mediaPresets: [[String: Any]] { // 引擎 schema 表单定义任意字段，保留其动态值。
        guard path == ["services"] else { return [] }
        return mediaCatalog(in: model.section)?["presets"] as? [[String: Any]] ?? []
    }
    var body: some View {
        SettingsPage(title: title) {
            beforeFields
            if (type == "object" || type == "intersect") && path.isEmpty && model.section.id.hasSuffix("-sandbox") {
                let primary = ["timeoutMs", "maxOutputBytes"]
                SettingsGroup {
                    ForEach(orderedKeys.filter { primary.contains($0) }, id: \.self) { key in
                        field(key, node: fields[key] ?? [:])
                    }
                }
                SettingsGroup(header: "More") {
                    ForEach(orderedKeys.filter { !primary.contains($0) }, id: \.self) { key in
                        field(key, node: fields[key] ?? [:])
                    }
                }
            } else {
                SettingsGroup(header: fieldsTitle) {
                    if type == "object" || type == "intersect" {
                        ForEach(orderedKeys, id: \.self) { key in field(key, node: fields[key] ?? [:]) }
                    } else if type == "array" {
                        let list = model.value(path) as? [Any] ?? []
                        ForEach(list.indices, id: \.self) { index in
                            field(String(index), node: model.schema.resolve(resolved["inner"] ?? [:]))
                                .contextMenu {
                                    Button("Remove", role: .destructive) { remove(String(index)) }
                                        .disabled(readOnly || model.containsSecret(path))
                                }
                        }
                    } else if type == "dict" {
                        ForEach((model.value(path) as? [String: Any] ?? [:]).keys.sorted(), id: \.self) { key in
                            field(key, node: model.schema.resolve(resolved["inner"] ?? [:]))
                                .contextMenu {
                                    Button("Remove", role: .destructive) { remove(key) }.disabled(readOnly || model.containsSecret(path))
                                }
                        }
                    } else {
                        SettingsRow(title: "This setting format is not supported.") { EmptyView() }
                    }
                }
            }
            if !mediaPresets.isEmpty && type == "array" {
                Menu("Add service from catalog") {
                    ForEach(Array(mediaPresets.enumerated()), id: \.offset) { _, preset in
                        Button(presetLabel(preset)) { addPreset(preset) }
                    }
                }.foregroundStyle(theme.accent).disabled(readOnly || model.saving || model.containsSecret(path)).padding(.bottom, 16)
            }
            if type == "array" || type == "dict" {
                MistButton(title: "Add item", kind: .secondary) {
                    if type == "dict" { key = ""; addKey = true }
                    else {
                        let inner = model.schema.resolve(resolved["inner"] ?? [:])
                        var list = model.value(path) as? [Any] ?? []
                        list.append(model.schema.defaultValue(inner)); model.set(path, list)
                    }
                }.disabled(readOnly || model.saving || model.containsSecret(path)).padding(.bottom, 16)
            }
            if let error = model.error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger).padding(.bottom, 12) }
            if model.hasEdits || model.saving {
                MistButton(title: "Save changes", busy: model.saving) { Task { await model.save(chat) } }
                    .disabled(readOnly || model.saving)
            }
            if !model.section.writable { Text("This host’s settings are read-only.").settingsType(.bodySmall).foregroundStyle(DS.inkFaint) }
            if !fields.isEmpty {
                MistButton(title: "Field descriptions", kind: .secondary) { showDocumentation = true }.padding(.top, Space.md)
            }
            afterFields.padding(.top, Space.xl)
        }
        .sheet(isPresented: $showDocumentation) {
            SettingsSheet(title: "Field descriptions", locked: true) {
                ScrollView {
                    SheetGroup {
                        ForEach(orderedKeys, id: \.self) { key in
                            let field = EngineFieldRules(schema: model.schema, node: fields[key] ?? [:])
                            if !field.hidden {
                                SettingsRow(title: LocalizedStringKey(field.title ?? fieldTitle(key)), subtitle: field.description) { EmptyView() }
                            }
                        }
                    }
                }
            }.presentationDetents([.large])
        }
        .sheet(item: $editing) { destination in
            EngineFieldEditor(model: model, path: destination.path, node: destination.node, readOnly: readOnly)
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
    private var fieldsTitle: LocalizedStringKey? {
        guard path.isEmpty else { return nil }
        switch model.section.id {
        case "subagent": return "Delegation limits"
        case "web-search-deepseek", "web-deepseek-api": return "DeepSeek"
        default: return nil
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
    @ViewBuilder private func field(_ key: String, node raw: [String: Any]) -> some View {
        let next = path + [key]
        let rules = EngineFieldRules(schema: model.schema, node: model.schema.effective(raw))
        if !rules.hidden {
            if rules.collapsed && rules.group {
                Button {
                    if !expanded.insert(key).inserted { expanded.remove(key) }
                } label: {
                    SettingsRow(title: LocalizedStringKey(rules.title ?? fieldTitle(key)), subtitle: rules.description) {
                        Glyph(glyph: expanded.contains(key) ? .caretUp : .caretDown, size: 16)
                    }
                }.buttonStyle(SettingsPressStyle())
                ExpandReveal(open: expanded.contains(key)) {
                    VStack(spacing: Space.xxs) {
                        let children = model.schema.fields(rules.node)
                        ForEach(children.keys.sorted(), id: \.self) { child in
                            valueRow(next + [child], key: child,
                                     rules: EngineFieldRules(schema: model.schema, node: children[child] ?? [:]))
                        }
                    }.padding(.leading, Space.sm)
                }
            } else {
                valueRow(next, key: key, rules: rules)
            }
        }
    }

    @ViewBuilder private func valueRow(_ next: [String], key: String, rules: EngineFieldRules) -> some View {
        if !rules.hidden {
            let secret = rules.secret || model.section.secretFields.contains(next)
            let locked = rules.locked || readOnly
            let label = LocalizedStringKey(rules.title ?? fieldTitle(key))
            let detail = locked ? String(localized: "Read-only on this host") : rules.description
            let value = model.value(next)
            if !secret && rules.type == "boolean" {
                SettingsToggleRow(title: label, subtitle: detail, isOn: Binding(
                    get: { model.value(next) as? Bool ?? false },
                    set: { model.set(next, $0) }
                ))
                .disabled(locked || model.saving)
                .settingAnchor(spotID(next))
            } else if !secret && (rules.group || ["array", "dict"].contains(rules.type)) {
                SettingsLink(title: label, subtitle: detail, value: collectionSummary(value)) {
                    EngineFormPage(model: model, displayTitle: label, path: next, node: rules.node, inheritedLock: locked)
                }
                .settingAnchor(spotID(next))
            } else {
                Button { editing = EngineFieldDestination(path: next, node: rules.node) } label: {
                    SettingsRow(title: label, subtitle: detail,
                                value: secret ? (model.section.secretPaths.contains(next) ? "••••" : String(localized: "Not set"))
                                              : rules.containsSecret() ? nil : fieldSummary(value, key: key, rules: rules)) {
                        if model.modified(next) && !secret && !locked {
                            Text("Modified").settingsType(.labelMedium)
                                .foregroundStyle(DS.inkMuted).padding(.horizontal, Space.sm)
                                .background(DS.searchFill, in: Capsule())
                        }
                        SettingsChevron()
                    }
                }
                .buttonStyle(SettingsPressStyle())
                .disabled(readOnly && secret || model.saving || (!secret && (rules.containsSecret() || model.containsSecret(next))))
                .settingAnchor(spotID(next))
            }
        }
    }

    private func spotID(_ path: [String]) -> String {
        if path == ["timeoutMs"], model.section.id.hasSuffix("-sandbox") { return "command-timeout" }
        return model.section.id + "." + path.joined(separator: ".")
    }

    private func collectionSummary(_ value: Any?) -> String? {
        if let list = value as? [Any] { return String(localized: "\(list.count) item(s)") }
        return nil
    }

    private func fieldSummary(_ value: Any?, key: String, rules: EngineFieldRules) -> String? {
        if rules.type == "bitset", let number = value as? Int {
            let selected = rules.bits.keys.sorted().filter { number & (rules.bits[$0] ?? 0) != 0 }
            return selected.isEmpty ? String(localized: "None") : selected.joined(separator: " · ")
        }
        if let collection = collectionSummary(value) { return collection }
        if let number = value as? NSNumber, rules.type == "number" {
            return engineNumberLabel(number.doubleValue, key: key)
        }
        return displayValue(value)
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
    @State private var hostGeneration: Int?
    var body: some View {
        NavigationStack {
            SettingsPage(title: "API key", showsBack: false) {
                Text(verbatim: reference).font(Mono.font(13, scale: theme.readingScale)).foregroundStyle(DS.inkMuted).padding(.bottom, 12)
                SecureField("API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled().padding(16).glass(.card)
                if let error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger) }
                MistButton(title: "Save", busy: busy) {
                    guard hostGeneration == chat.connection.generation else { error = "E_SETTINGS_HOST_CHANGED"; return }
                    busy = true
                    Task {
                        do { try await chat.connection.credentialsAPI.set(ref: reference, value: key); key = ""; dismiss() }
                        catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
                        busy = false
                    }
                }.disabled(key.isEmpty || busy).padding(.top, 12)
            }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.onAppear { hostGeneration = chat.connection.generation }.onDisappear { key = "" }
    }
}

func displayValue(_ value: Any?) -> String {
    guard let value, !(value is NSNull) else { return "" }
    if let text = value as? String { return text }
    return String(describing: value)
}
func fieldTitle(_ key: String) -> String {
    switch key {
    case "apiKey": String(localized: "API key")
    case "keyRef", "apiKeyEnv": String(localized: "API key reference")
    case "baseURL", "baseUrl": String(localized: "API base URL")
    case "timeoutMs": String(localized: "Command timeout")
    case "maxOutputBytes": String(localized: "Output limit")
    case "maxTimeoutMs": String(localized: "Max requested timeout")
    case "maxSpillBytes": String(localized: "Spill file limit")
    case "graceMs": String(localized: "Termination grace period")
    case "maxDepth": String(localized: "Maximum recursion depth")
    case "maxActive", "maxActiveSubagents": String(localized: "Max active subagents")
    case "maxParallelToolCalls": String(localized: "Max parallel tool calls")
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

func engineNumberLabel(_ value: Double, key: String) -> String {
    if key.hasSuffix("Ms") {
        if value >= 60_000 && value.truncatingRemainder(dividingBy: 60_000) == 0 {
            return String(localized: "\((value / 60_000).formatted()) min")
        }
        return String(localized: "\((value / 1000).formatted(.number.precision(.fractionLength(0...3)))) s")
    }
    if key.hasSuffix("Bytes"), let bytes = Int64(exactly: value) {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }
    return value.formatted()
}
