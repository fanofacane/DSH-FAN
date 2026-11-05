// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/settings/settings_screen.dart and ui/engine/engine_status.dart.
import DSHClient
import DSHRuntime
import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var chat
    @Environment(EngineModel.self) private var engine
    @Environment(PhoneController.self) private var phone
    @Environment(PetModel.self) private var pet
    @Environment(HostStore.self) private var hosts
    @Environment(AppPreferences.self) private var preferences
    @Environment(TaskNotifications.self) private var notifications
    @Environment(\.dismiss) private var dismiss

    @State private var path: [SettingsLocation]

    init(startAtRemote: Bool = false, initial: SettingsLocation? = nil) {
        _path = State(initialValue: initial.map { [$0] } ?? (startAtRemote ? [SettingsLocation("remote")] : []))
    }
    @State private var personalPreferencesSet: Bool?

    private var fixture: String? {
        #if DEBUG
        return DebugPageRegistry.usesFixture ? DebugPageRegistry.argument("-dsh-screen-fixture") : nil
        #else
        return nil
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            hub(target: nil, close: { dismiss() })
            .navigationDestination(for: SettingsLocation.self) { location in
                if location.page == "search" {
                    SettingsSearchPage(context: context, open: { path.append($0) }, ask: fixture != nil || chat.connection.state == .ready ? ask : nil)
                } else if location.page == "settings" {
                    hub(target: location.anchor, close: nil)
                } else {
                    SettingsRegistry.destination(location)
                }
            }
        }
        .task(id: chat.connection.state == .ready ? chat.connection.generation : -1) {
            guard fixture == nil, !hosts.isRemote, engine.status.phase == .running else {
                personalPreferencesSet = nil
                return
            }
            let summary = try? await engine.runtime.replyPreferences()
            guard !Task.isCancelled else { return }
            personalPreferencesSet = summary.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        .sheet(item: Binding(get: { hosts.hostKeyPrompt }, set: { _ in })) { prompt in HostKeySheet(prompt: prompt) }
    }

    private func hub(target: String?, close: (() -> Void)?) -> some View {
        SettingsPage(title: "Settings", backAction: close) {
                Button { path.append(SettingsLocation("search")) } label: {
                    SearchCapsuleShape {
                        Text("Search settings").frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(SettingsPressStyle(scales: true))
                .padding(.bottom, Space.lg)
                SettingsOverview(fixture: fixture, open: open)
                ForEach(SettingsSection.allCases) { group in
                    settingsGroup(group, context: context)
                }
                BrandMark(size: 18)
                    .opacity(0.35).frame(maxWidth: .infinity).padding(.top, Space.sm)
            }
        .environment(\.settingsTarget, target)
    }

    private var context: SettingsContext {
        if let fixture {
            return SettingsContext(isRemote: fixture == "remote-only", hostName: fixture == "remote-only" ? "实验室服务器" : nil,
                                   savedHostCount: fixture == "full" || fixture == "remote-only" ? 1 : 0,
                                   presetName: fixture == "full" ? String(localized: "Full access") : nil,
                                   presetRisk: fixture == "full", personalPreferencesSet: fixture == "remote-only" ? nil : false,
                                   appearanceName: String(localized: "Follow system"), version: "1.0.11")
        }
        let preset = chat.control.permissionPreset ?? chat.control.enginePermissionDefault
        return SettingsContext(isRemote: hosts.isRemote, hostName: hosts.activeHost?.name, savedHostCount: hosts.hosts.count,
                               presetName: chat.control.permissionPresets.first { $0.id == preset }?.name,
                               presetRisk: ["auto", "danger-full-access"].contains(preset),
                               personalPreferencesSet: hosts.isRemote ? nil : personalPreferencesSet,
                               phoneEnabled: phone.enabled, petName: pet.pack?.displayName,
                               appearanceName: appearanceName, notificationsEnabled: notifications.enabled,
                               version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
    }

    private var appearanceName: String {
        switch preferences.appearance {
        case "light": String(localized: "Light")
        case "dark": String(localized: "Dark")
        default: String(localized: "Follow system")
        }
    }

    @ViewBuilder private func settingsGroup(_ group: SettingsSection, context: SettingsContext) -> some View {
        SettingsGroup(header: LocalizedStringKey(group.rawValue)) {
            ForEach(SettingsRegistry.entries(in: group)) { entry in
                if group == .appearance && entry.id == "pet" {
                    ChatReadingSettingsRows(tone: group.tone)
                }
                if group == .general && entry.id == "notifications" {
                    LanguageSettingsRow(tone: group.tone)
                }
                Button { open(entry.id) } label: {
                    if entry.id == "engine" {
                        let status = SettingsEngineStatus(phase: fixture == "remote-only" ? .notInstalled : fixture != nil ? .running : engine.status.phase,
                                                          safe: fixture == nil && engine.safeModeOn)
                        SettingsRow(glyph: entry.glyph, tone: group.tone, title: entry.title, tinted: true) {
                            HStack(spacing: Space.xs) {
                                StatusChip(tone: status.tone, label: LocalizedStringKey(status.label))
                                SettingsChevron()
                            }
                        }
                    } else {
                        SettingsRow(glyph: entry.glyph, tone: group.tone, title: entry.title,
                                    tinted: true, value: entry.value(context), valueColor: context.presetRisk && entry.id == "permissions" ? DS.warn : DS.inkMuted)
                    }
                }
                .buttonStyle(SettingsPressStyle())
            }
        }
    }

    private func open(_ id: String) { path.append(SettingsLocation(id)) }

    private func ask(_ query: String) {
        guard fixture == nil else { return }
        chat.transcript.newChat()
        chat.transcript.incomingDraft = SharedDraft(text: query, images: [])
        dismiss()
    }
}

struct ChatReadingSettingsRows: View {
    let tone: TileTone
    var tinted = true
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        SettingsSegmentRow(glyph: AppIcon.textSize, tone: tone, tinted: tinted, title: "Chat text size",
                           segments: [.init(0.9, String(localized: "Small")), .init(1, String(localized: "Standard")),
                                      .init(1.15, String(localized: "Large")), .init(1.3, String(localized: "Extra large"))],
                           selection: Binding(get: { preferences.textScaleChoice }, set: { preferences.textScale = $0 }))
            .settingAnchor("chat-text-size")
        SettingsToggleRow(glyph: AppIcon.foldTurns, tone: tone, title: "Collapse steps when done",
                          tinted: tinted, isOn: $preferences.foldCompletedTurns)
            .settingAnchor("fold-turns")
    }
}

struct LanguageSettingsRow: View {
    let tone: TileTone
    var tinted = true
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        SettingsSegmentRow(glyph: AppIcon.translate, tone: tone, tinted: tinted, title: "Language",
                           segments: [.init("system", String(localized: "System")), .init("zh-Hans", "中文"), .init("en", "English")],
                           selection: $preferences.language)
            .settingAnchor("language")
    }
}

func effortTitle(_ effort: ReasoningEffort) -> String {
    switch effort.id {
    case "off": String(localized: "Off")
    case "low": String(localized: "Low")
    case "high": String(localized: "High")
    case "max": String(localized: "Max")
    default: effort.name
    }
}

// MARK: Pages

struct KeySettingsPage: View {
    @Environment(AppSession.self) private var chat
    @State private var confirmClear = false
    var body: some View {
        SettingsPage(title: "API key") {
            SettingsGroup {
                SettingsRow(glyph: AppIcon.apiKey, tone: .ai, title: "DeepSeek API key",
                            subtitle: chat.connection.keyConfigured ? String(localized: "Configured") : String(localized: "Not set")) { EmptyView() }
            }
            KeySetupCard().padding(.bottom, 22)
            if chat.connection.keyConfigured && chat.connection.keyWritable {
                MistButton(title: "Remove key", kind: .danger) { confirmClear = true }
            }
        }
        .confirmationDialog("Remove the API key from this device?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Remove key", role: .destructive) { Task { await chat.connection.clearKey() } }
        }
    }
}

struct ModelSettingsPage: View {
    @Environment(AppSession.self) private var chat
    var body: some View {
        SettingsPage(title: "Model") {
            SettingsGroup(header: "Default model") {
                ForEach(Array(chat.connection.models.enumerated()), id: \.element.id) { index, model in
                    SettingsChoiceRow(title: model.name, selected: chat.connection.selectedModel == model) { chat.connection.selectedModel = model }
                }
            }
            if let model = chat.connection.selectedModel, !model.efforts.isEmpty {
                SettingsGroup(header: "Thinking", footer: "Deeper thinking answers harder questions better but takes longer.") {
                    ForEach(Array(model.efforts.enumerated()), id: \.element.id) { index, effort in
                        SettingsChoiceRow(title: effortTitle(effort), selected: (chat.connection.effort(for: model) ?? model.efforts[0].id) == effort.id) {
                            chat.connection.setEffort(effort.id, for: model)
                        }
                    }
                }
            }
        }
    }
}

struct PermissionSettingsPage: View {
    @Environment(AppSession.self) private var chat
    var body: some View {
        SettingsPage(title: "Permissions") {
            SettingsGroup(header: "New chats", footer: "iOS has no command sandbox for the engine, so full access is the default here; the app itself stays inside the iOS sandbox. Choose a stricter preset to approve actions yourself.") {
                SettingsChoiceRow(title: String(localized: "Engine default"), selected: chat.control.permissionPreset == nil) { chat.control.permissionPreset = nil }
                ForEach(chat.control.permissionPresets) { preset in
                    SettingsChoiceRow(title: preset.name, subtitle: preset.description, selected: chat.control.permissionPreset == preset.id) {
                        chat.control.permissionPreset = preset.id
                    }
                }
            }.settingAnchor("default-permission")
        }
    }
}

extension RuntimePhase {
    var titleResource: String.LocalizationValue {
        switch self {
        case .notInstalled: "Not installed"
        case .installing: "Installing"
        case .installed: "Installed"
        case .starting: "Starting"
        case .running: "Running"
        case .stopping: "Stopping"
        case .error: "Error"
        }
    }
}
