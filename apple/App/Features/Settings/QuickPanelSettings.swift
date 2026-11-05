// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/settings/quick_panel_items_sheet.dart and ui/shell/quick_panel.dart.
import SwiftUI

enum QuickPanelItem: String, CaseIterable, Identifiable {
    case workspaces, schedules, agents, usage, remote, providers

    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .workspaces: "Workspaces"
        case .schedules: "Scheduled tasks"
        case .agents: "Agent presets"
        case .usage: "Run insights"
        case .remote: "Remote hosts"
        case .providers: "Models"
        }
    }
    var glyph: DshGlyph {
        switch self {
        case .workspaces: .folder
        case .schedules: .calendar
        case .agents: AppIcon.profile
        case .usage: AppIcon.history
        case .remote: AppIcon.remoteHosts
        case .providers: AppIcon.providers
        }
    }
}

struct QuickPanelSettingsSection: View {
    @Environment(AppPreferences.self) private var preferences
    @State private var showItems = false

    var body: some View {
        @Bindable var preferences = preferences
        SettingsGroup(header: "Swipe-left shortcuts") {
            SettingsToggleRow(title: "Open with a left swipe",
                              subtitle: String(localized: "Swipe left from the right edge of the chat."),
                              isOn: $preferences.quickPanelEnabled)
                .settingAnchor("quick-panel")
            Button { showItems = true } label: {
                SettingsRow(title: "What it lists", value: String(preferences.quickPanelItems.count))
            }.buttonStyle(SettingsPressStyle())
        }
        .sheet(isPresented: $showItems) { QuickPanelItemsSheet() }
    }
}

struct QuickPanelItemsSheet: View {
    @Environment(AppPreferences.self) private var preferences
    @State private var rows: [QuickPanelItem] = []

    var body: some View {
        SettingsSheet(title: "What it lists", locked: true) {
            List {
                ForEach(rows) { row in
                    let selected = preferences.quickPanelItems.contains(row)
                    Button {
                        if selected { preferences.quickPanelItems.removeAll { $0 == row } }
                        else { preferences.quickPanelItems = rows.filter { $0 == row || preferences.quickPanelItems.contains($0) } }
                    } label: {
                        SettingsRow(glyph: row.glyph, title: row.title) {
                            Image(systemName: selected ? "checkmark.square.fill" : "square").foregroundStyle(DS.inkMuted)
                        }
                    }
                    .buttonStyle(SettingsPressStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onMove { from, to in
                    rows.move(fromOffsets: from, toOffset: to)
                    preferences.quickPanelItems = rows.filter { preferences.quickPanelItems.contains($0) }
                }
            }
            .environment(\.editMode, .constant(.active))
            .listStyle(.plain).scrollContentBackground(.hidden).glass(.card, radius: Radius.lg)
        }
        .onAppear {
            rows = preferences.quickPanelItems + QuickPanelItem.allCases.filter { !preferences.quickPanelItems.contains($0) }
        }
        .presentationDetents([.medium, .large])
    }
}

struct QuickPanelSheet: View {
    let items: [QuickPanelItem]
    let open: (QuickPanelItem) -> Void

    var body: some View {
        SettingsSheet(title: "Swipe-left shortcuts") {
            SheetGroup {
                ForEach(items) { item in
                    Button { open(item) } label: { SettingsRow(glyph: item.glyph, title: item.title) }
                        .buttonStyle(SettingsPressStyle())
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
