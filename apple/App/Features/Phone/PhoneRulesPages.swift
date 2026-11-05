// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/phone/{phone_control_screen,app_rules_page,action_log_page,phone_widgets}.dart.
import DSHPhone
import SwiftUI

extension ConfirmMode {
    var settingsLabel: String.LocalizationValue {
        switch self {
        case .ask: "Ask every time"
        case .task: "Allow within a task"
        case .always: "Don't ask"
        }
    }

    var settingsHint: String.LocalizationValue {
        switch self {
        case .ask: "Confirm each phone action."
        case .task: "Allow more actions in the same task after you approve it."
        case .always: "Run most actions without asking."
        }
    }
}

struct PhoneConfirmModePage: View {
    @Environment(PhoneController.self) private var phone
    @State private var showRisk = false

    var body: some View {
        SettingsPage(title: "Confirmation mode") {
            SheetGroup {
                ForEach(ConfirmMode.allCases, id: \.self) { mode in
                    SettingsChoiceRow(title: String(localized: mode.settingsLabel),
                                      subtitle: String(localized: mode.settingsHint),
                                      selected: phone.mode == mode) {
                        guard phone.mode != mode else { return }
                        if mode == .always { showRisk = true }
                        else { phone.setMode(mode) }
                    }
                }
            }
            Text("Calls, messages, sharing, reading the clipboard and the first run of each shortcut always ask.")
                .settingsType(.bodySmall).foregroundStyle(DS.inkFaint).padding(Space.sm)
        }
        .sensoryFeedback(.selection, trigger: phone.mode)
        .sheet(isPresented: $showRisk) {
            RiskNoticeSheet(title: "Allow most actions without asking?",
                            message: "The agent can use enabled system features and allowed shortcuts while a task runs. Sensitive actions still ask.",
                            action: "Don't ask") { _ in phone.setMode(.always) }
        }
    }
}

struct PhoneRulesPage: View {
    @Environment(PhoneController.self) private var phone
    @State private var newShortcut = ""
    private var name: String { newShortcut.trimmingCharacters(in: .whitespaces) }
    private var shortcuts: Set<String> {
        #if DEBUG
        if DebugPageRegistry.usesFixture { return ["Open Calendar", "Start focus timer"] }
        #endif
        return phone.shortcuts
    }

    var body: some View {
        SettingsPage(title: "App rules") {
            SettingsGroup(header: "Allowed shortcuts", footer: "The model can only run shortcuts you add here, with the exact name. It cannot change this list.") {
                ForEach(shortcuts.sorted(), id: \.self) { name in
                    SettingsRow(glyph: .lightning, title: "", verbatim: name) {
                        Button {
                            phone.setShortcuts(phone.shortcuts.subtracting([name]))
                        } label: {
                            Glyph(glyph: AppIcon.close, size: 16).foregroundStyle(DS.inkFaint)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(SettingsPressStyle())
                        .accessibilityLabel(Text("Remove"))
                    }
                }
                HStack(spacing: Space.md) {
                    TextField("Shortcut name", text: $newShortcut)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .settingsType(.setting)
                    Button("Add") {
                        if phone.setShortcuts(phone.shortcuts.union([name])) { newShortcut = "" }
                    }
                    .settingsType(.label)
                    .disabled(!PhoneController.validShortcut(name) || shortcuts.contains(name) || shortcuts.count >= 32)
                }
                .padding(.horizontal, SettingsMetrics.inset).frame(minHeight: SettingsMetrics.row)
            }
        }
    }
}

struct PhoneActionLogPage: View {
    @Environment(PhoneController.self) private var phone

    var body: some View {
        SettingsPage(title: "Phone action log") {
            SettingsGroup(footer: "Only action types, times and outcomes are kept for this app session.") {
                if phone.actionHistory.isEmpty {
                    SettingsRow(glyph: AppIcon.history, title: "No phone actions yet") { EmptyView() }
                }
                ForEach(phone.actionHistory) { PhoneActionRow(action: $0) }
            }
        }
    }
}

struct PhoneActionRow: View {
    let action: PhoneActionEvent

    var body: some View {
        SettingsRow(glyph: AppIcon.history, title: action.title,
                    subtitle: action.date.formatted(date: .abbreviated, time: .shortened)) {
            Text(action.outcome.label).settingsType(.bodySmall)
                .foregroundStyle(action.outcome == .failed || action.outcome == .denied ? DS.danger : DS.inkMuted)
        }
    }
}

extension PhoneActionEvent {
    var title: LocalizedStringKey {
        switch kind {
        case "open": "Open an app or link"
        case "intent": "Use a system feature"
        case "notify": "Send a notification"
        case "clipboard": "Use the clipboard"
        case "shortcut": "Run a shortcut"
        case "handoff": "Hand off to you"
        default: "Phone action"
        }
    }
}

extension PhoneActionEvent.Outcome {
    var label: LocalizedStringKey {
        switch self {
        case .completed: "Completed"
        case .submitted: "Submitted"
        case .denied: "Denied"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        }
    }
}
