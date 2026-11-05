// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/engine_settings/{field_sheets,sequence_field,bitset_field}.dart.
import DSHClient
import SwiftUI

struct EngineFieldDestination: Identifiable {
    var id: [String] { path }
    let path: [String]
    let node: [String: Any] // Host-provided Schemastery document.
}

struct EngineFieldEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: EngineFormModel
    let path: [String]
    let node: [String: Any] // Host-provided Schemastery document.
    var readOnly = false
    @State private var text = ""
    @State private var selected: Int?
    @State private var mask = 0
    @State private var invalid = false
    @State private var showCredential = false

    private var rules: EngineFieldRules { EngineFieldRules(schema: model.schema, node: node) }
    private var key: String { path.last ?? "" }
    private var secret: Bool { rules.secret || model.section.secretFields.contains(path) }
    private var numberScale: Double { key.hasSuffix("Ms") ? 1000 : 1 }
    private var isNumeric: Bool { rules.type == "number" }
    private var acceptsJSON: Bool { ["any", "tuple", "union"].contains(rules.type) }
    private var credentialReference: String? {
        let parent = Array(path.dropLast())
        for key in ["credentialRef", "keyRef", "apiKeyEnv"] {
            if let ref = model.value(parent + [key]) as? String, !ref.isEmpty { return ref }
        }
        if key == "apiKey", ["web-search-deepseek", "web-deepseek-api"].contains(model.section.id) { return "DEEPSEEK_API_KEY" }
        return nil
    }

    var body: some View {
        SettingsSheet(title: LocalizedStringKey(rules.title ?? fieldTitle(key)), locked: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.md) {
                    if let description = rules.description {
                        Text(description).settingsType(.bodyMedium).foregroundStyle(DS.inkMuted)
                    }
                    SheetGroup { editor }.disabled(readOnly || rules.locked)
                    if invalid {
                        Text("Enter a valid value.").settingsType(.bodySmall).foregroundStyle(DS.danger)
                    }
                }
            }.scrollBounceBehavior(.basedOnSize)
            if !secret {
                HStack(spacing: Space.md) {
                    if rules.meta["nullable"] as? Bool == true {
                        MistButton(title: "Clear value", kind: .secondary) { model.set(path, NSNull()); dismiss() }
                    } else if model.modified(path) {
                        MistButton(title: "Reset to default", kind: .secondary) { model.restore(path); dismiss() }
                    }
                    MistButton(title: "Apply to draft", action: apply)
                        .disabled(rules.locked || !model.section.writable)
                }.disabled(readOnly || rules.locked)
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { load() }
        .onChange(of: text) { invalid = false }
        .sheet(isPresented: $showCredential) {
            if let credentialReference { CredentialKeyEditor(reference: credentialReference) }
        }
    }

    @ViewBuilder private var editor: some View {
        if secret {
            if credentialReference != nil {
                Button { showCredential = true } label: { SettingsRow(title: "Configure referenced key") }
                    .buttonStyle(SettingsPressStyle())
            } else {
                Text("This host does not expose a credential reference for this field.")
                    .settingsType(.bodyMedium).padding(Space.lg)
            }
        } else if let choices = rules.choices {
            ForEach(Array(choices.enumerated()), id: \.offset) { index, value in
                SettingsChoiceRow(title: value is NSNull ? String(localized: "None") : displayValue(value),
                                  selected: selected == index) { selected = index }
            }
        } else if rules.type == "bitset", !rules.bits.isEmpty {
            ForEach(rules.bits.keys.sorted(), id: \.self) { label in
                let bit = rules.bits[label] ?? 0
                SettingsToggleRow(title: LocalizedStringKey(label), isOn: Binding(
                    get: { mask & bit != 0 },
                    set: { on in mask = on ? mask | bit : mask & ~bit }
                )).disabled(bit == 0)
            }
        } else if isNumeric {
            HStack(spacing: Space.md) {
                stepKey("Decrease", symbol: "minus", by: -1)
                TextField("Value", text: $text)
                    .font(Mono.font(17)).multilineTextAlignment(.center)
                    .keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
                if numberScale != 1 { Text("s").settingsType(.bodySmall).foregroundStyle(DS.inkFaint) }
                stepKey("Increase", symbol: "plus", by: 1)
            }.padding(Space.md)
            if let min = rules.minimum, let max = rules.maximum, min.isFinite, max.isFinite, min < max {
                let step = rules.step ?? ((max - min) / 100)
                let divisions = (max - min) / step
                if step > 0, divisions.isFinite, (1...200).contains(divisions),
                   abs(divisions - divisions.rounded()) < 0.000001 {
                    Slider(value: Binding(
                        get: { Swift.max(min, Swift.min(max, (Double(text) ?? min / numberScale) * numberScale)) },
                        set: { newValue in text = displayValue((newValue / numberScale * 1_000_000).rounded() / 1_000_000) }
                    ), in: min...max, step: step)
                    .padding(.horizontal, Space.lg).accessibilityLabel(Text("Value"))
                }
            }
        } else if acceptsJSON || rules.role == "textarea" {
            TextEditor(text: $text).font(Mono.font()).scrollContentBackground(.hidden)
                .frame(minHeight: 120).padding(Space.md).accessibilityLabel(Text("Value"))
        } else if rules.type == "string" {
            TextField("Value", text: $text, axis: .vertical)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(key.lowercased().contains("url") ? .URL : .default)
                .padding(Space.lg)
        } else {
            Text("This setting format is not supported.").settingsType(.bodyMedium).padding(Space.lg)
        }
    }

    private func stepKey(_ label: LocalizedStringKey, symbol: String, by direction: Int) -> some View {
        Button {
            let step = rules.step ?? numberScale
            let initial = (Double(text) ?? 0) * numberScale
            let next = initial + Double(direction) * step
            if rules.valid(next) { text = displayValue((next / numberScale * 1_000_000).rounded() / 1_000_000) }
        } label: {
            Image(systemName: symbol).frame(width: 44, height: 44).background(DS.searchFill, in: Circle())
        }.buttonStyle(SettingsPressStyle(scales: true)).accessibilityLabel(Text(label))
    }

    private func load() {
        guard !secret else { return }
        let value = model.value(path) ?? rules.meta["default"]
        if let choices = rules.choices {
            selected = choices.firstIndex { engineValueEqual(value, $0) }
        } else if rules.type == "bitset" {
            mask = value as? Int ?? 0
        } else if isNumeric, let number = value as? NSNumber {
            text = displayValue(number.doubleValue / numberScale)
        } else if let value, acceptsJSON,
                  let bytes = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) {
            text = String(decoding: bytes, as: UTF8.self)
        } else {
            text = displayValue(value)
        }
    }

    private func apply() {
        let value: Any?
        if let choices = rules.choices {
            value = selected.flatMap { choices.indices.contains($0) ? choices[$0] : nil }
        } else if rules.type == "bitset" {
            value = mask
        } else if isNumeric {
            value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)).map { $0 * numberScale }
        } else if acceptsJSON {
            value = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
        } else {
            value = text
        }
        guard let value, rules.valid(value) else { invalid = true; return }
        model.set(path, value)
        dismiss()
    }
}
