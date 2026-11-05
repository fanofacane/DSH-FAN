// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/engine_settings/engine_settings_hub.dart.
import DSHClient
import SwiftUI

struct EngineParametersPage: View {
    @Environment(AppSession.self) private var chat
    @State private var sections: [EngineNamespace] = []
    @State private var error: String?
    var body: some View {
        SettingsPage(title: "Engine parameters") {
            SettingsGroup {
                ForEach(sections) { section in
                    NavigationLink { EngineFormPage(model: EngineFormModel(section)) } label: {
                        SettingsRow(title: "Engine parameters", verbatim: section.id) { SettingsChevron() }
                    }.buttonStyle(.plain)
                }
                if sections.isEmpty && error == nil { Text("No editable parameters reported by this host.").type(.bodyMedium).padding(16) }
            }
            if let error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger) }
        }.task(id: chat.connection.state) {
            guard chat.connection.state == .ready else { return }
            do {
                sections = try await chat.connection.settingsAPI.describe().filter {
                    ["subagent", "subagent-model-selection-settings", "agent-loop", "bash-sandbox", "pwsh-sandbox"].contains($0.id)
                }; error = nil
            } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
        }
    }
}
