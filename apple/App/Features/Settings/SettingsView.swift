// SPDX-License-Identifier: AGPL-3.0-or-later
// Settings hub and pages in the Mist Glass style (原 Flutter 版 lib/ui/settings).
import DSHClient
import DSHRuntime
import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var chat
    @Environment(EngineModel.self) private var engine
    @Environment(PhoneController.self) private var phone
    @Environment(PetModel.self) private var pet
    @Environment(HostStore.self) private var hosts
    @Environment(\.dismiss) private var dismiss
    /// Opened from the host switcher: push the remote hosts page.
    var startAtRemote = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            SettingsPage(title: "Settings", showsBack: false) {
                headerCard
                ForEach(SettingsRegistry.sections) { group in
                    settingsGroup(group)
                }
            }
            .overlay(alignment: .topTrailing) {
                GlassIconButton(glyph: AppIcon.close, label: "Done") { dismiss() }
                    .padding(.trailing, 12).padding(.top, 4)
            }
            .navigationDestination(for: String.self) { SettingsRegistry.destination($0) }
        }
        .onAppear { if startAtRemote && path.isEmpty { path.append("remote") } }
        .sheet(item: Binding(get: { hosts.hostKeyPrompt }, set: { _ in })) { prompt in HostKeySheet(prompt: prompt) }
    }

    private var context: SettingsContext {
        SettingsContext(isRemote: hosts.isRemote, modelSubtitle: modelSubtitle, presetName: presetName,
                        remoteSubtitle: hosts.activeHost.map { String(localized: "Using “\($0.name)”") } ?? String(localized: "This phone"),
                        phoneEnabled: phone.enabled, petEnabled: pet.enabled,
                        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
    }

    private func settingsGroup(_ group: SettingsSection) -> some View {
        let entries = SettingsRegistry.entries(in: group, context: context)
        return SettingsGroup(header: LocalizedStringKey(group.rawValue)) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                SettingsLink(glyph: entry.glyph, tone: entry.tone, title: entry.title, subtitle: entry.subtitle(context)) {
                    entry.destination()
                }
            }
        }
    }

    /// Account card: key status, then the engine line (settings_signed_in golden).
    private var headerCard: some View {
        VStack(spacing: 0) {
            NavigationLink { SettingsRegistry.key.destination() } label: {
                HStack(spacing: 16) {
                    Glyph(glyph: AppIcon.apiKey, size: 26).foregroundStyle(DS.dusk)
                        .frame(width: 52, height: 52).background(DS.duskContainer, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "DeepSeek API").font(.system(size: 17, weight: .semibold)).foregroundStyle(DS.ink)
                        Text(chat.connection.keyConfigured ? "Key configured" : "No key yet").font(.system(size: 14))
                            .foregroundStyle(chat.connection.keyConfigured ? DS.inkMuted : DS.warn)
                    }
                    Spacer()
                    SettingsChevron()
                }
                .padding(16).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            NavigationLink { SettingsRegistry.engine.destination() } label: {
                HStack(spacing: 12) {
                    Circle().fill(engine.status.phase == .running ? DS.success : DS.warn).frame(width: 8, height: 8)
                        .frame(width: 52)
                    Text(engineLine).font(.system(size: 13)).foregroundStyle(DS.inkMuted).lineLimit(1)
                    Spacer()
                    SettingsChevron()
                }
                .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .glass(.card, radius: Radius.lg)
        .padding(.bottom, 22)
    }

    private var engineLine: String {
        var parts = [String(localized: "Local engine"), String(localized: engine.status.phase.titleResource)]
        if let dsh = engine.status.dshVersion { parts.append("DSH \(dsh)") }
        return parts.joined(separator: " · ")
    }

    private var modelSubtitle: String? {
        guard let model = chat.connection.selectedModel else { return nil }
        let effort = chat.connection.effort(for: model).flatMap { id in model.efforts.first { $0.id == id } }
        return [ChatHeaderView.shortName(model.name), effort.map { effortTitle($0) }].compactMap { $0 }.joined(separator: " · ")
    }

    private var presetName: String? {
        let id = chat.control.permissionPreset ?? chat.control.enginePermissionDefault
        return chat.control.permissionPresets.first { $0.id == id }?.name
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
            }
        }
    }
}

struct PetSettingsPage: View {
    @Environment(PetModel.self) private var pet
    var body: some View {
        @Bindable var pet = pet
        SettingsPage(title: "Pet") {
            SettingsGroup(footer: "Deepy stands on the composer and reacts to what the agent is doing. Tap it to say hi.") {
                SettingsToggleRow(glyph: AppIcon.pet, tone: .ability, title: "Deepy the whale", isOn: $pet.enabled)
            }
            if pet.enabled {
                SettingsGroup(header: "Size") {
                    SettingsChoiceRow(title: String(localized: "Small"), selected: pet.bodyHeight == 22) { pet.bodyHeight = 22 }
                    SettingsChoiceRow(title: String(localized: "Standard"), selected: pet.bodyHeight == 30) { pet.bodyHeight = 30 }
                    SettingsChoiceRow(title: String(localized: "Large"), selected: pet.bodyHeight == 40) { pet.bodyHeight = 40 }
                }
            }
        }
    }
}

struct AboutPage: View {
    @Environment(EngineModel.self) private var engine
    var body: some View {
        SettingsPage(title: "About DSH Fan") {
            SettingsGroup {
                SettingsRow(title: "Version") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "").foregroundStyle(DS.inkFaint)
                }
                if let dsh = engine.status.dshVersion {
                    SettingsRow(title: "DSH") { Text(dsh).foregroundStyle(DS.inkFaint) }
                }
                if let node = engine.status.nodeVersion {
                    SettingsRow(title: "Node.js") { Text(node).foregroundStyle(DS.inkFaint) }
                }
            }
            SettingsGroup(header: "Open source") {
                Text("DSH Fan is an independent project that learned from DSH Go (AGPL-3.0) and iSH (GPL-3.0). It is open source under AGPL-3.0; the source code is at github.com/fanofacane/dsh-fan.")
                    .type(.bodyMedium).foregroundStyle(DS.inkMuted).padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
