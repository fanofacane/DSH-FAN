// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/settings/search/{settings_search,settings_search_page}.dart.
import SwiftUI

struct SettingsSearchPage: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.locale) private var locale
    let context: SettingsContext
    let open: (SettingsLocation) -> Void
    let ask: ((String) -> Void)?
    @State private var query = ""

    private var fixture: Bool {
        #if DEBUG
        DebugPageRegistry.usesFixture
        #else
        false
        #endif
    }

    private var chinese: Bool { locale.language.languageCode?.identifier == "zh" }
    private var recent: [String] { fixture ? ["保活", "api key"] : preferences.recentSettingsSearches }
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hits: [SettingsIndex.Hit] { SettingsIndex.search(trimmed, in: SettingsIndex.spots) }

    var body: some View {
        SettingsPage(title: "Search settings", showsTitle: false) {
            SearchCapsule(hint: "Search settings", query: $query, autoFocus: !fixture)
                .padding(.top, 6).padding(.bottom, Space.xl)
            if trimmed.isEmpty {
                idle
            } else if hits.isEmpty {
                noResults
            } else {
                results("Settings", hits.filter { !$0.spot.feature })
                results("Features", hits.filter { $0.spot.feature })
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            #if DEBUG
            if fixture { query = DebugPageRegistry.argument("-dsh-screen-query") ?? "" }
            #endif
        }
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Popular searches").settingsType(.label).foregroundStyle(DS.inkFaint)
                .accessibilityAddTraits(.isHeader).padding(.leading, Space.sm)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.sm) { suggestions }
                VStack(alignment: .leading, spacing: Space.sm) { suggestions }
            }
            .padding(.bottom, Space.lg)
            if !recent.isEmpty {
                SettingsGroup(header: "Recent searches", rowGap: 0) {
                    ForEach(recent, id: \.self) { term in
                        Button { query = term } label: {
                            SettingsRow(glyph: AppIcon.history, title: "", verbatim: term) { EmptyView() }
                        }.buttonStyle(SettingsPressStyle())
                    }
                }
            }
        }
    }

    private var suggestions: some View {
        ForEach(["Dark mode", "Background", "Permissions", "Text size"], id: \.self) { label in
            CapsuleChoiceChip(label: LocalizedStringKey(label), selected: false) {
                query = SettingsIndex.translated(label, chinese: chinese)
            }
        }
    }

    private var noResults: some View {
        VStack(spacing: Space.md) {
            Glyph(glyph: AppIcon.noResults, size: 32).foregroundStyle(DS.inkFaint)
            Text("No settings found").settingsType(.titleMedium)
            if let ask {
                Button {
                    remember()
                    ask(trimmed)
                } label: {
                    Label("Ask AI about “\(trimmed)”", systemImage: "sparkle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.inkMuted)
                .settingsType(.bodyMedium)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.xxxl)
    }

    @ViewBuilder private func results(_ title: LocalizedStringKey, _ hits: [SettingsIndex.Hit]) -> some View {
        if !hits.isEmpty {
            SettingsGroup(header: title, rowGap: 0) {
                ForEach(hits) { hit in
                    let spot = hit.spot
                    let unavailable = spot.localOnly && context.isRemote
                    let path = spot.path.map { SettingsIndex.translated($0, chinese: chinese) }.joined(separator: " › ")
                    let route = unavailable ? SettingsLocation(SettingsRegistry.entry(spot.location.page)?.parent ?? "settings") : spot.location
                    Button { remember(); open(route) } label: {
                        ListPageSearchRow(title: LocalizedStringKey(spot.key), synonym: hit.synonym,
                                          path: unavailable ? String(localized: "Available with the local engine") : path)
                    }
                    .buttonStyle(SettingsPressStyle())
                }
            }
        }
    }

    private func remember() {
        if !fixture { preferences.rememberSettingsSearch(trimmed) }
    }
}

private struct ListPageSearchRow: View {
    let title: LocalizedStringKey
    let synonym: String?
    let path: String

    var body: some View {
        HStack(spacing: Space.xs) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(spacing: Space.xs) {
                    Text(title).lineLimit(1).layoutPriority(1)
                    if let synonym { Text("· " + synonym).lineLimit(1).foregroundStyle(DS.inkFaint) }
                }.settingsType(.setting)
                Text(path).settingsType(.bodySmall).foregroundStyle(DS.inkFaint).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SettingsChevron()
        }
        .padding(.leading, SettingsMetrics.inset)
        .padding(.trailing, SettingsMetrics.trailingInset)
        .padding(.vertical, 10)
        .frame(minHeight: SettingsMetrics.detailRow)
        .contentShape(Rectangle())
    }
}
