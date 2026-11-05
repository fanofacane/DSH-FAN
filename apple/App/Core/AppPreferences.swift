// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import DSHRuntime
import Observation
import SwiftUI

// DSH Go: app/lib/state/settings_state.dart and ui/settings/search/settings_search_page.dart.
@Observable final class AppPreferences {
    private let defaults: UserDefaults
    var appearance: String { didSet { defaults.set(appearance, forKey: "ui.appearance") } }
    var palette: String { didSet { defaults.set(palette, forKey: "ui.palette") } }
    var textScale: Double { didSet { defaults.set(textScale, forKey: "ui.textScale") } }
    var remoteImages: Bool { didSet { defaults.set(remoteImages, forKey: "privacy.remoteImages") } }
    var foldCompletedTurns: Bool { didSet { defaults.set(foldCompletedTurns, forKey: "ui.foldCompletedTurns") } }
    var reduceMotion: Bool { didSet { defaults.set(reduceMotion, forKey: "ui.reduceMotion") } }
    var glassBlur: Bool { didSet { defaults.set(glassBlur, forKey: "ui.glassBlur") } }
    var voiceInputEnabled: Bool { didSet { defaults.set(voiceInputEnabled, forKey: "ui.voiceInput") } }
    var quickPanelEnabled: Bool { didSet { defaults.set(quickPanelEnabled, forKey: "ui.quickPanel") } }
    var quickPanelItems: [QuickPanelItem] { didSet { defaults.set(quickPanelItems.map(\.rawValue), forKey: "ui.quickPanel.items") } }
    var language: String {
        didSet {
            defaults.set(language, forKey: "ui.language")
            if language == "system" { defaults.removeObject(forKey: "AppleLanguages") }
            else { defaults.set([language], forKey: "AppleLanguages") }
        }
    }
    private(set) var recentSettingsSearches: [String] {
        didSet { defaults.set(recentSettingsSearches, forKey: "settings_search.recent") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: "ui.appearance") ?? "system"
        palette = defaults.string(forKey: "ui.palette") ?? "mist"
        textScale = defaults.object(forKey: "ui.textScale") as? Double ?? 1
        remoteImages = defaults.object(forKey: "privacy.remoteImages") as? Bool ?? true
        foldCompletedTurns = defaults.object(forKey: "ui.foldCompletedTurns") as? Bool ?? true
        reduceMotion = defaults.bool(forKey: "ui.reduceMotion")
        glassBlur = defaults.object(forKey: "ui.glassBlur") as? Bool ?? true
        voiceInputEnabled = defaults.object(forKey: "ui.voiceInput") as? Bool ?? true
        quickPanelEnabled = defaults.bool(forKey: "ui.quickPanel")
        let savedItems = defaults.stringArray(forKey: "ui.quickPanel.items")?.compactMap(QuickPanelItem.init(rawValue:))
        var seen: Set<QuickPanelItem> = []
        quickPanelItems = (savedItems ?? QuickPanelItem.allCases).filter { seen.insert($0).inserted }
        language = defaults.string(forKey: "ui.language") ?? "system"
        recentSettingsSearches = Array((defaults.stringArray(forKey: "settings_search.recent") ?? []).prefix(5))
    }

    func rememberSettingsSearch(_ query: String) {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        recentSettingsSearches = Array(([term] + recentSettingsSearches.filter { $0 != term }).prefix(5))
    }

    var colorScheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
    var scale: CGFloat { CGFloat(min(1.3, max(0.9, textScale.isFinite ? textScale : 1))) }
    var textScaleChoice: Double {
        [0.9, 1, 1.15, 1.3].min { abs($0 - Double(scale)) < abs($1 - Double(scale)) } ?? 1
    }
}

struct AppearanceSettingsPage: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppPreferences.self) private var preferences
    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage(title: "Theme") {
            SettingsGroup(header: "Color mode") {
                SettingsChoiceRow(title: "Follow system", selected: preferences.appearance == "system") { preferences.appearance = "system" }
                SettingsChoiceRow(title: "Light", selected: preferences.appearance == "light") { preferences.appearance = "light" }
                SettingsChoiceRow(title: "Dark", selected: preferences.appearance == "dark") { preferences.appearance = "dark" }
            }.settingAnchor("theme-mode")
            SettingsGroup(header: "Accent color") {
                SettingsChoiceRow(title: "Mist blue", selected: preferences.palette == "mist") { preferences.palette = "mist" }
                SettingsChoiceRow(title: "Teal", selected: preferences.palette == "teal") { preferences.palette = "teal" }
                SettingsChoiceRow(title: "Plum", selected: preferences.palette == "plum") { preferences.palette = "plum" }
            }.settingAnchor("accent")
            SettingsGroup(header: "Reading text size", footer: "Applies to body text and code. Navigation controls keep their standard size.") {
                Slider(value: $preferences.textScale, in: 0.9...1.3, step: 0.1).tint(theme.accent).padding(16)
                    .accessibilityLabel("Reading text size")
                Text("Preview: a clear answer with readable code.").type(.body).foregroundStyle(DS.ink).padding(16)
            }
        }
    }
}

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

struct PrivacySettingsPage: View {
    @Environment(\.openURL) private var openURL
    @Environment(AppPreferences.self) private var preferences
    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage(title: "Privacy and sharing") {
            SettingsGroup(footer: "External image hosts receive your network request. Turn this off to load each external image only when you choose.") {
                SettingsToggleRow(title: "Load external message images", isOn: $preferences.remoteImages).settingAnchor("remote-images")
            }
            SettingsGroup {
                Text("Model credentials stay in the selected engine’s credential store. Remote connection secrets are stored in iOS Keychain.").type(.bodyMedium).foregroundStyle(DS.ink).padding(16)
                Text("DSH does not automatically upload diagnostic logs. Review every export before sharing it.").type(.bodyMedium).foregroundStyle(DS.ink).padding(16)
                Text("Choose notification, photo, microphone and speech permissions in iOS Settings.").type(.bodyMedium).foregroundStyle(DS.ink).padding(16)
                Button { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } } label: { SettingsRow(title: "Open iOS Settings") }.buttonStyle(.plain)
            }
        }
    }
}

enum DiagnosticExport {
    static func writeReviewed(_ text: String, reviewed: Bool) throws -> URL {
        guard reviewed else { throw DSHError("E_DIAGNOSTICS_REVIEW") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DSH-diagnostics-" + UUID().uuidString + ".txt")
        try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}

struct DiagnosticsSettingsPage: View {
    @Environment(\.designTheme) private var theme
    @Environment(EngineModel.self) private var engine
    @State private var draft = ""
    @State private var reviewed = false
    @State private var export: URL?
    @State private var error: String?
    var body: some View {
        SettingsPage(title: "Diagnostics") {
            SettingsGroup(footer: "This is a redacted snapshot of local engine logs. Automatic redaction is not a guarantee. Remove secrets and personal information before exporting.") {
                TextEditor(text: $draft).font(Mono.font(11, scale: theme.readingScale)).frame(minHeight: 300).scrollContentBackground(.hidden).padding(12)
            }
            SettingsGroup {
                SettingsToggleRow(title: "I reviewed this text for secrets", isOn: $reviewed)
            }
            if let export {
                ShareLink(item: export) { Label("Share reviewed log", systemImage: "square.and.arrow.up").type(.label) }.padding(16)
            } else {
                MistButton(title: "Prepare reviewed log") {
                    do { export = try DiagnosticExport.writeReviewed(draft, reviewed: reviewed); error = nil }
                    catch { self.error = (error as? DSHError)?.code ?? "E_DIAGNOSTICS_EXPORT" }
                }.disabled(!reviewed || draft.isEmpty)
            }
            if let error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger) }
            Text("Only local engine logs are included; remote host logs are not collected.").type(.bodySmall).foregroundStyle(DS.inkFaint).padding(.top, 16)
        }
        .onAppear { draft = engine.logs.map { "[\($0.stream)] " + RuntimeLogs.redact($0.line) }.joined(separator: "\n") }
        .onChange(of: draft) { _, _ in reviewed = false; clearExport() }
        .onChange(of: reviewed) { _, value in if !value { clearExport() } }
        .onDisappear { clearExport() }
    }
    private func clearExport() { if let export { try? FileManager.default.removeItem(at: export) }; export = nil }
}

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
