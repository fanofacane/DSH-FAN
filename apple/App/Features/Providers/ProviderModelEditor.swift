// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/providers/{provider_model_page,model_context_page}.dart.
import SwiftUI

struct ProviderModelEditor: View {
    @Environment(\.dismiss) private var dismiss
    let original: [String: Any]?
    let reservedIDs: Set<String>
    let apply: ([String: Any]) -> Void
    @State private var id = ""
    @State private var name = ""
    @State private var contextWindow = ""
    @State private var maxTokens = ""

    private var trimmedID: String { id.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool {
        !trimmedID.isEmpty && trimmedID.count <= 256
            && (original != nil || !reservedIDs.contains(trimmedID))
            && [contextWindow, maxTokens].allSatisfy { $0.isEmpty || (Int($0) ?? 0) > 0 }
            && (Int(maxTokens) ?? 0) <= (Int(contextWindow) ?? Int.max)
    }

    var body: some View {
        SettingsSheet(title: original == nil ? "Add model" : "Model settings", locked: true) {
            ScrollView {
                SheetGroup {
                    TextField("Model ID", text: $id)
                        .disabled(original != nil).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().padding(Space.lg)
                    TextField("Display name", text: $name).padding(Space.lg)
                    TextField("Context window", text: $contextWindow).keyboardType(.numberPad).padding(Space.lg)
                    TextField("Maximum output tokens", text: $maxTokens).keyboardType(.numberPad).padding(Space.lg)
                }
            }.scrollBounceBehavior(.basedOnSize)
            MistButton(title: "Apply to draft") {
                var value = original ?? [:]
                value["id"] = trimmedID
                value["name"] = name.isEmpty ? nil : name
                value["contextWindow"] = Int(contextWindow)
                value["maxTokens"] = Int(maxTokens)
                apply(value)
                dismiss()
            }.disabled(!valid)
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            id = original?["id"] as? String ?? ""
            name = original?["name"] as? String ?? ""
            contextWindow = (original?["contextWindow"] as? Int).map(String.init) ?? ""
            maxTokens = (original?["maxTokens"] as? Int).map(String.init) ?? ""
        }
    }
}
