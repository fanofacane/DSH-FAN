// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/phone/{phone_control_screen,phone_widgets,phone_disclosure_sheet}.dart.
import DSHPhone
import SwiftUI

struct PhoneSettingsView: View {
    @Environment(PhoneController.self) private var phone
    @Environment(EngineModel.self) private var engine
    @Environment(HostStore.self) private var hosts
    @Environment(\.openURL) private var openURL
    @AppStorage("phone_ios.v1.disclosure") private var acknowledged = false
    @State private var disclose = false

    private var enabled: Bool {
        #if DEBUG
        if DebugPageRegistry.usesFixture { return DebugPageRegistry.argument("-dsh-screen-fixture") != "off" }
        #endif
        return phone.enabled
    }

    var body: some View {
        SettingsPage(title: "Phone control") {
            OverviewCard(title: Text("Phone control"),
                         subtitle: Text(enabled ? "Use this phone in an agent task" : "Off")) {
                SettingsIcon(glyph: AppIcon.phoneControl, tone: .identity(6), size: 52)
            } accessory: {
                Button { setEnabled(!enabled) } label: { MistSwitch(isOn: enabled) }
                    .buttonStyle(SettingsPressStyle()).accessibilityLabel(Text("Phone control"))
                    .accessibilityValue(Text(enabled ? "On" : "Off"))
                    .sensoryFeedback(.selection, trigger: enabled)
                    .disabled(phone.busy || !phone.available)
            } footer: {
                OverviewFooter(tone: enabled ? .ok : .idle, text: Text(enabled ? "On" : "Off"))
            }
            if phone.busy || phone.lastError != nil {
                Text(phone.busy ? String(localized: "Restarting the local engine…") : (phone.lastError ?? ""))
                    .settingsType(.bodySmall).foregroundStyle(phone.busy ? DS.inkMuted : DS.danger)
                    .padding(.horizontal, Space.sm).padding(.bottom, Space.md)
            }
            if enabled && engine.safeModeOn {
                SettingsGroup(footer: "The local engine is in safe mode, so the model can't use phone control.") {
                    Button { engine.startNormal() } label: {
                        SettingsRow(glyph: AppIcon.safeMode, tone: .neutral, title: "Start normally")
                    }
                    .buttonStyle(SettingsPressStyle())
                    .disabled(engine.busy || phone.busy || engine.status.restartRequired)
                }
            } else if enabled && hosts.activeHost != nil {
                SettingsGroup {
                    SettingsRow(glyph: AppIcon.info, title: "Phone tools are available on the local engine.") { EmptyView() }
                }
            }
            if !enabled {
                SettingsGroup(header: "What it can do") {
                    SettingsRow(glyph: AppIcon.calendar, title: "Use system features",
                                subtitle: String(localized: "Alarms, calendars, reminders and notifications")) { EmptyView() }
                    SettingsRow(glyph: .lightning, title: "Run allowed shortcuts",
                                subtitle: String(localized: "You choose which shortcuts the model can run.")) { EmptyView() }
                }
            }
            SettingsGroup(header: "Rules") {
                SettingsLink(glyph: .listChecks, title: "App rules",
                             subtitle: String(localized: "\(phone.shortcuts.count) allowed shortcut(s)")) {
                    PhoneRulesPage()
                }
                SettingsLink(glyph: AppIcon.approval, title: "Confirmation mode",
                             subtitle: String(localized: phone.mode.settingsLabel)) { PhoneConfirmModePage() }
                    .settingAnchor("phone-confirm")
            }
            SettingsGroup(header: "Recent actions") {
                if phone.actionHistory.isEmpty {
                    SettingsRow(glyph: AppIcon.history, title: "No phone actions yet",
                                subtitle: String(localized: "Actions appear here after the agent uses phone control.")) { EmptyView() }
                } else {
                    ForEach(phone.actionHistory.prefix(3)) { PhoneActionRow(action: $0) }
                }
                SettingsLink(glyph: AppIcon.history, title: "All actions") { PhoneActionLogPage() }
            }
            SettingsGroup(header: "System permissions") {
                permissionRow(.alarm, "Alarms", "alarm")
                permissionRow(AppIcon.calendar, "Calendar", "calendar")
                permissionRow(.listChecks, "Reminders", "reminder")
                permissionRow(.bell, "Notifications", "notify")
                permissionRow(.lightning, "Shortcuts app", "shortcut")
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    SettingsRow(glyph: AppIcon.systemAccess, title: "Open system settings")
                }.buttonStyle(SettingsPressStyle())
            }
        }
        .task {
            #if DEBUG
            if DebugPageRegistry.usesFixture { return }
            #endif
            await phone.refreshCapabilities()
        }
        .sheet(isPresented: $disclose) {
            PhoneDisclosureSheet {
                acknowledged = true
                Task { await phone.setEnabled(true) }
            }
        }
    }

    private func setEnabled(_ value: Bool) {
        #if DEBUG
        if DebugPageRegistry.usesFixture { return }
        #endif
        if value && !acknowledged { disclose = true }
        else { Task { await phone.setEnabled(value) } }
    }

    private func permissionRow(_ glyph: DshGlyph, _ title: LocalizedStringKey, _ key: String) -> some View {
        let state = phone.capabilities[key]
        return SettingsRow(glyph: glyph, title: title) {
            Group {
                switch state {
                case "authorized", "writeOnly", "available": Text("Allowed").foregroundStyle(DS.success)
                case "denied": Text("Denied").foregroundStyle(DS.danger)
                case "unsupported", "unavailable": Text("Unavailable").foregroundStyle(DS.inkFaint)
                case "notDetermined": Text("Asks on first use").foregroundStyle(DS.inkFaint)
                default: Text("Unknown").foregroundStyle(DS.inkFaint)
                }
            }.settingsType(.bodySmall)
        }
    }
}

struct PhoneDisclosureSheet: View {
    let enable: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsSheet(title: "Enable phone control?") {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.md) {
                    Text("Phone control lets the local engine ask DSH Fan to act on this iPhone.")
                        .settingsType(.bodyMedium).foregroundStyle(DS.inkMuted)
                    SheetGroup {
                        detail(.eye, "What it can access", "The agent can request supported system actions and shortcuts you allow.")
                        detail(.clock, "When it runs", "Phone actions run while the app is in the foreground and phone control is on.")
                        detail(.globe, "Who gets the result", "The result returns to the local engine. Your model provider may receive it as part of the conversation.")
                        detail(.shield, "What always asks", "Calls, messages, sharing, clipboard reads and each shortcut’s first run still ask.")
                        detail(.handPalm, "How to stop it", "Stop the task or turn off phone control here.")
                    }
                    Text("Changing this setting can restart the local engine.")
                        .settingsType(.bodySmall).foregroundStyle(DS.inkFaint)
                }
            }.scrollBounceBehavior(.basedOnSize)
            HStack(spacing: Space.md) {
                MistButton(title: "Not now", kind: .secondary) { dismiss() }
                MistButton(title: "Agree and enable") { dismiss(); enable() }
            }
        }.presentationDetents([.large])
    }

    private func detail(_ glyph: DshGlyph, _ title: LocalizedStringKey, _ body: String.LocalizationValue) -> some View {
        SettingsRow(glyph: glyph, title: title, subtitle: String(localized: body)) { EmptyView() }
    }
}
