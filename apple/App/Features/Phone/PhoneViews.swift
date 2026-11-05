// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHPhone
import SwiftUI
import UIKit

struct PhoneSettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(PhoneController.self) private var phone
    @Environment(EngineModel.self) private var engine
    @State private var newShortcut = ""

    var body: some View {
        SettingsPage(title: "Phone control") {
            SettingsGroup(footer: "Lets the model set alarms, add calendar events and reminders, navigate, send notifications and run shortcuts you allow. iOS does not allow reading the screen or tapping in other apps.") {
                SettingsToggleRow(glyph: AppIcon.phoneControl, tone: .ability, title: "Phone control",
                                  subtitle: phone.busy ? String(localized: "Restarting the local engine…") : phone.lastError,
                                  isOn: Binding(get: { phone.enabled }, set: { value in Task { await phone.setEnabled(value) } }))
                    .disabled(phone.busy || !phone.available)
            }

            if phone.enabled && engine.safeModeOn {
                // Safe mode never mounts the phone overlay, so the model sees no phone tools.
                SettingsGroup(footer: "The local engine is in safe mode, so the model can't use phone control.") {
                    Button { engine.startNormal() } label: {
                        SettingsRow(glyph: AppIcon.safeMode, tone: .neutral, title: "Start normally")
                    }
                    .buttonStyle(.plain)
                    .disabled(engine.busy || phone.busy || engine.status.restartRequired)
                }
            }

            SettingsGroup(header: "Confirmation", footer: "Calls, messages, sharing, reading the clipboard and the first run of each shortcut always ask.") {
                SettingsChoiceRow(title: String(localized: "Ask every time"), selected: phone.mode == .ask) { phone.setMode(.ask) }
                SettingsChoiceRow(title: String(localized: "Allow within a task"), selected: phone.mode == .task) { phone.setMode(.task) }
                SettingsChoiceRow(title: String(localized: "Don't ask"), selected: phone.mode == .always) { phone.setMode(.always) }
            }

            SettingsGroup(header: "Allowed shortcuts", footer: "The model can only run shortcuts you add here, with the exact name. It cannot change this list.") {
                ForEach(phone.shortcuts.sorted(), id: \.self) { name in
                    SettingsRow(glyph: DshGlyph.lightning, tone: .neutral, title: LocalizedStringKey(name)) {
                        Button { phone.setShortcuts(phone.shortcuts.subtracting([name])) } label: {
                            Glyph(glyph: AppIcon.close, size: 16).foregroundStyle(DS.inkFaint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Remove"))
                    }
                }
                HStack(spacing: 10) {
                    TextField("Shortcut name", text: $newShortcut)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .font(.system(size: 16))
                    Button("Add") {
                        let name = newShortcut.trimmingCharacters(in: .whitespaces)
                        if phone.setShortcuts(phone.shortcuts.union([name])) { newShortcut = "" }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .disabled(!PhoneController.validShortcut(newShortcut.trimmingCharacters(in: .whitespaces)) || phone.shortcuts.count >= 32)
                }
                .padding(.horizontal, 16).frame(minHeight: 56)
            }

            SettingsGroup(header: "System permissions") {
                permissionRow(DshGlyph.alarm, "Alarms", phone.capabilities["alarm"])
                permissionRow(AppIcon.calendar, "Calendar", phone.capabilities["calendar"])
                permissionRow(DshGlyph.listChecks, "Reminders", phone.capabilities["reminder"])
                permissionRow(DshGlyph.bell, "Notifications", phone.capabilities["notify"])
                permissionRow(DshGlyph.lightning, "Shortcuts app", phone.capabilities["shortcut"])
            }
            MistButton(title: "Open system settings", kind: .secondary) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
        .task { await phone.refreshCapabilities() }
    }

    private func permissionRow(_ glyph: DshGlyph, _ title: LocalizedStringKey, _ state: String?) -> some View {
        SettingsRow(glyph: glyph, tone: .neutral, title: title) {
            switch state {
            case "authorized", "writeOnly", "available": Text("Allowed").font(.system(size: 14)).foregroundStyle(DS.success)
            case "denied": Text("Denied").font(.system(size: 14)).foregroundStyle(DS.danger)
            case "unsupported", "unavailable": Text("Unavailable").font(.system(size: 14)).foregroundStyle(DS.inkFaint)
            case "notDetermined": Text("Asks on first use").font(.system(size: 14)).foregroundStyle(DS.inkFaint)
            default: Text(verbatim: "—").foregroundStyle(DS.inkFaint)
            }
        }
    }
}

/// Confirmation for a phone action requested by the model.
struct PhoneConfirmSheet: View {
    @Environment(\.designTheme) private var theme
    @Environment(PhoneController.self) private var phone
    let prompt: PhonePrompt

    var body: some View {
        ZStack {
            AppBackdrop(glow: false)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Glyph(glyph: prompt.name == "handoff" ? DshGlyph.handTap : AppIcon.approval, size: 22)
                        .foregroundStyle(prompt.name == "handoff" ? theme.accent : DS.warn)
                    Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(DS.ink)
                }
                .padding(.top, 24)
                Text(prompt.name == "handoff"
                     ? "Do this yourself, then come back and choose Continue."
                     : "Only allow actions you expect. Denying stops this action.")
                    .type(.bodyMedium).foregroundStyle(DS.inkMuted)
                if !prompt.summary.isEmpty {
                    ScrollView { CodeBlockView(language: prompt.name, code: prompt.summary) }.frame(maxHeight: 260)
                }
                Spacer(minLength: 0)
                VStack(spacing: 10) {
                    if prompt.name == "handoff" {
                        MistButton(title: "Continue") { phone.answer(prompt.id, .once) }
                        MistButton(title: "Stop", kind: .danger) { phone.answer(prompt.id, .reject) }
                    } else {
                        MistButton(title: "Allow once") { phone.answer(prompt.id, .once) }
                        if prompt.allowTask {
                            MistButton(title: "Allow for this task", kind: .secondary) { phone.answer(prompt.id, .task) }
                        }
                        MistButton(title: "Deny", kind: .danger) { phone.answer(prompt.id, .reject) }
                    }
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
        }
        .interactiveDismissDisabled()
        .presentationDetents([.medium, .large])
    }

    private var title: LocalizedStringKey {
        switch prompt.name {
        case "handoff": "Your turn"
        case "open": "Open an app or link?"
        case "intent": "Use a system feature?"
        case "notify": "Send a notification?"
        case "clipboard": "Use the clipboard?"
        case "shortcut": "Run a shortcut?"
        default: "Allow this action?"
        }
    }
}
