// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/settings/reply_prefs_page.dart.
import DSHRuntime
import SwiftUI

struct ReplyPreferencesPage: View {
    @Environment(\.designTheme) private var theme
    @Environment(EngineModel.self) private var engine
    @Environment(HostStore.self) private var hosts
    @State private var text = ""
    @State private var saved = ""
    @State private var loaded = false
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        SettingsPage(title: "Personal preferences") {
            SettingsGroup(footer: "Personal instructions are stored in this phone’s shared AGENTS.md. Start a new conversation after saving. Do not enter credentials here.") {
                if hosts.isRemote { SettingsRow(title: "Reply preferences are available for this phone’s engine only.") { EmptyView() } }
                else { TextEditor(text: $text).font(Mono.font(scale: theme.readingScale)).frame(minHeight: 250).scrollContentBackground(.hidden).padding(12).disabled(!loaded || saving) }
            }
            if let error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger) }
            if !hosts.isRemote {
                MistButton(title: "Save", busy: saving) { Task {
                    saving = true; defer { saving = false }
                    do {
                        try await engine.runtime.saveReplyPreferences(text, expected: saved)
                        saved = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : text
                        text = saved; error = nil
                    }
                    catch { self.error = (error as? RuntimeError)?.code ?? "E_PREFERENCES_WRITE" }
                } }.disabled(!loaded || text == saved || text.utf8.count > 65536)
            }
        }.task {
            guard !hosts.isRemote else { return }
            do { text = try await engine.runtime.replyPreferences(); saved = text; loaded = true }
            catch { self.error = (error as? RuntimeError)?.code ?? "E_PREFERENCES_READ" }
        }
    }
}
