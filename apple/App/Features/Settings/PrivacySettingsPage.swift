// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/settings/{privacy_page,usage_stats_section}.dart.
// Configuration sharing uses the iOS share sheet and an allowlist of UI preferences.
import DSHClient
import SwiftUI

struct PrivacySettingsPage: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(AppSession.self) private var chat
    @State private var sharing = false
    @State private var upload: EngineNamespace?
    @State private var saving = false
    @State private var consent = false
    @State private var error: String?

    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage(title: "Privacy and sharing") {
            SettingsGroup(header: "Sharing") {
                Button { sharing = true } label: { SettingsRow(title: "Share configuration") }
                    .buttonStyle(SettingsPressStyle()).settingAnchor("share-configuration")
            }
            SettingsGroup(header: "Usage statistics", footer: "DSH Fan does not collect anonymous usage statistics.") {
                InfoRow(label: "Send anonymous usage statistics", value: String(localized: "Off"))
            }
            SettingsGroup(header: "Data",
                          footer: "External image hosts receive your network request. Turn this off to load each external image only when you choose.") {
                SettingsToggleRow(title: "Load external message images", isOn: $preferences.remoteImages)
                    .settingAnchor("remote-images")
                if let upload, let enabled = upload.value["enabled"] as? Bool {
                    SettingsToggleRow(title: "Upload chat logs to DeepSeek", isOn: Binding(get: { enabled }, set: { value in
                        if value { consent = true }
                        else { Task { await setUpload(false) } }
                    }))
                    .disabled(saving || !upload.writable)
                    .settingAnchor("chat-log-upload")
                }
            }
            if let error {
                Text("Request failed: \(error)").settingsType(.bodySmall).foregroundStyle(DS.danger)
                    .padding(.bottom, Space.lg)
            }
            SettingsGroup(header: "Credentials and diagnostics") {
                VStack(alignment: .leading, spacing: Space.md) {
                    Text("Model credentials stay in the selected engine’s credential store. Remote connection secrets are stored in iOS Keychain.")
                    Text("DSH does not automatically upload diagnostic logs. Review every export before sharing it.")
                }
                .settingsType(.bodyMedium).foregroundStyle(DS.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading).padding(Space.lg)
                SettingsLink(title: "System permissions") { SystemAccessPage() }
            }
        }
        .task(id: chat.connection.state == .ready ? chat.connection.generation : -1) { await load() }
        .sheet(isPresented: $sharing) {
            SettingsSheet(title: "Share configuration") {
                Text("Share theme, language and reading preferences. The export excludes conversations, credentials, hosts and photos.")
                    .settingsType(.bodyMedium).foregroundStyle(DS.inkMuted)
                if let config = configuration {
                    ShareLink(item: config) { SettingsRow(glyph: AppIcon.shareConfig, title: "Share configuration") }
                        .buttonStyle(SettingsPressStyle())
                }
            }.presentationDetents([.medium])
        }
        .sheet(isPresented: $consent) {
            RiskNoticeSheet(title: "Upload chat logs to DeepSeek?",
                            message: "This host may send conversation logs to DeepSeek. The setting applies to this host.",
                            action: "Allow upload") { _ in Task { await setUpload(true) } }
        }
    }

    private struct Configuration: Encodable {
        let schema = 1
        let appearance: String
        let palette: String
        let textScale: Double
        let language: String
        let foldCompletedTurns: Bool
    }

    private var configuration: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let value = Configuration(appearance: preferences.appearance, palette: preferences.palette,
                                  textScale: Double(preferences.scale), language: preferences.language,
                                  foldCompletedTurns: preferences.foldCompletedTurns)
        return try? String(decoding: encoder.encode(value), as: UTF8.self)
    }

    private func load() async {
        upload = nil; error = nil
        #if DEBUG
        if DebugPageRegistry.usesFixture {
            upload = EngineNamespace(["ns": "session-log-deepseek", "value": ["enabled": true]], writable: false)
            return
        }
        #endif
        guard chat.connection.state == .ready else { return }
        let generation = chat.connection.generation
        do {
            let settings = try await chat.connection.settingsAPI.describe()
            guard generation == chat.connection.generation, !Task.isCancelled else { return }
            upload = settings.first { $0.id == "session-log-deepseek" }
        } catch {
            if generation == chat.connection.generation, !Task.isCancelled { self.error = appErrorCode(error) }
        }
    }

    private func setUpload(_ enabled: Bool) async {
        guard let upload, upload.writable, !saving else { return }
        let generation = chat.connection.generation
        saving = true
        defer { saving = false }
        do {
            let result = try await chat.connection.settingsAPI.mutate(
                ns: upload.id, expectedRevision: upload.revision,
                ops: [["op": "set", "path": ["enabled"], "value": enabled]], writable: upload.writable
            )
            guard generation == chat.connection.generation else { return }
            self.upload = result
            error = nil
        } catch {
            if generation == chat.connection.generation { self.error = appErrorCode(error) }
        }
    }
}
