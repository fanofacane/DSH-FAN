// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/features/permission_page.dart.
import DSHClient
import DSHPhone
import SwiftUI

struct PermissionSettingsPage: View {
    @Environment(AppSession.self) private var chat
    @Environment(PhoneController.self) private var phone
    @State private var pending: PermissionPreset?

    private var options: [PermissionPreset] {
        #if DEBUG
        if DebugPageRegistry.usesFixture {
            return [
                PermissionPreset(id: "read-only", name: String(localized: "Read only"),
                                 description: String(localized: "Ask before changing anything.")),
                PermissionPreset(id: "workspace-write", name: String(localized: "Workspace access"),
                                 description: String(localized: "Allow changes in the workspace.")),
                PermissionPreset(id: "danger-full-access", name: String(localized: "Full access"),
                                 description: String(localized: "Allow commands without per-action approval.")),
            ]
        }
        #endif
        return chat.control.permissionPresets.filter { $0.id != "custom" }
    }

    var body: some View {
        SettingsPage(title: "Permissions", subtitle: "Choose when the engine should ask for approval.") {
            SettingsGroup(header: "New chat default",
                          footer: "iOS has no command sandbox for the engine, so full access is the default here; the app itself stays inside the iOS sandbox. Choose a stricter preset to approve actions yourself.") {
                SettingsChoiceRow(title: String(localized: "Engine default"), selected: chat.control.permissionPreset == nil) {
                    chat.control.permissionPreset = nil
                }
                ForEach(options) { preset in
                    SettingsChoiceRow(title: preset.name, subtitle: preset.description,
                                      selected: chat.control.permissionPreset == preset.id) {
                        guard preset.id != chat.control.permissionPreset else { return }
                        if ["danger-full-access", "auto"].contains(preset.id) { pending = preset }
                        else { chat.control.permissionPreset = preset.id }
                    }
                }
                if let code = chat.control.permissionError {
                    SettingsRow(title: "Couldn't read permissions", subtitle: code, titleColor: DS.danger) { EmptyView() }
                    Button {
                        if let client = chat.connection.client { Task { await chat.control.loadPermissions(client) } }
                    } label: { SettingsRow(title: "Retry") }
                    .buttonStyle(SettingsPressStyle())
                }
            }.settingAnchor("default-permission")
            SettingsGroup(header: "Phone control") {
                SettingsLink(glyph: AppIcon.phoneControl, title: "Confirmation mode",
                             value: String(localized: phone.mode.settingsLabel)) {
                    PhoneSettingsView().environment(\.settingsTarget, "phone-confirm")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: chat.control.permissionPreset)
        .sheet(item: $pending) { preset in
            RiskNoticeSheet(title: "Allow more actions without asking?",
                            message: "The selected preset changes how much the engine can do before asking for approval in new chats.",
                            action: "Use this preset") { _ in
                if options.contains(where: { $0.id == preset.id }) { chat.control.permissionPreset = preset.id }
            }
        }
    }
}
