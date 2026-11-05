// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import SwiftUI
import Testing
@testable import DSH

@MainActor struct RegistryTests {
    @Test func settingsKeepGroupOrderAndLocalAccountBoundary() throws {
        #expect(SettingsSection.allCases == [.ai, .abilities, .appearance, .general, .hosts, .help])
        #expect(SettingsRegistry.entries(in: .ai).map(\.id) == ["providers", "permissions", "personalization"])
        #expect(SettingsRegistry.entries(in: .abilities).map(\.id) == ["phone", "web-search", "media"])
        #expect(SettingsRegistry.entries(in: .appearance).map(\.id) == ["appearance", "pet"])
        #expect(SettingsRegistry.entries(in: .general).map(\.id) == ["interface", "notifications", "voice", "performance", "background", "system-access", "privacy"])
        #expect(SettingsRegistry.entries(in: .hosts).map(\.id) == ["engine", "remote", "engine-parameters"])
        #expect(SettingsRegistry.entries(in: .help).map(\.id) == ["help", "diagnostics", "about"])
        #expect(try #require(SettingsRegistry.entry("account")).localOnly)
        #expect(try #require(SettingsRegistry.entry("reply-preferences")).localOnly)
        #expect(Set(SettingsIndex.spots.map(\.id)).count == SettingsIndex.spots.count)
    }

    @Test func settingsSearchRanksBilingualTitlesAndSynonyms() {
        let spots = SettingsIndex.spots
        let hits = SettingsIndex.search(" 别问我 ", in: spots)
        #expect(hits.first?.spot.id == "permissions")
        #expect(hits.first?.synonym == "别问我")
        #expect(hits.dropFirst().first?.spot.location == SettingsLocation("permissions", anchor: "default-permission"))
        #expect(hits.dropFirst(2).first?.spot.location == SettingsLocation("phone", anchor: "phone-confirm"))
        #expect(SettingsIndex.search("ＡＰＩ　ＫＥＹ", in: spots).first?.spot.id == "key")
        #expect(SettingsIndex.search("隐私与分享", in: spots).first?.spot.id == "privacy")
        #expect(SettingsIndex.search("　 ", in: spots).isEmpty)
        #expect(SettingsIndex.location(forLink: "models") == SettingsLocation("providers"))
        #expect(SettingsIndex.location(forLink: "unknown") == nil)
    }

    @Test func settingsSegmentFitsAtMeasuredBoundary() {
        #expect(SegmentRowLayout.fitsInline(title: 90, pill: 190, available: 296))
        #expect(!SegmentRowLayout.fitsInline(title: 90, pill: 190, available: 295.9))
        #expect(!SegmentRowLayout.fitsInline(title: 180, pill: 190, available: 330))
    }

    @Test func preferencesPersistSearchAndLayoutSettings() throws {
        let suite = "DSHSettingsTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1.1, forKey: "ui.textScale")
        let first = AppPreferences(defaults: defaults)
        #expect(first.scale == 1.1)
        #expect(first.textScaleChoice == 1.15)
        first.textScale = 1.3
        first.foldCompletedTurns = false
        first.glassBlur = false
        first.quickPanelItems = [.agents, .schedules]
        for word in ["dark", "permissions", "text", "privacy", "background", "speech", "  text  "] {
            first.rememberSettingsSearch(word)
        }
        let second = AppPreferences(defaults: defaults)
        #expect(second.textScale == 1.3)
        #expect(!second.foldCompletedTurns)
        #expect(!second.glassBlur)
        #expect(second.quickPanelItems == [.agents, .schedules])
        #expect(second.recentSettingsSearches == ["text", "speech", "background", "privacy", "permissions"])
    }

    @Test func toolFamiliesPreserveLabelsIconsAndSummaries() {
        let cases: [(String, [String: JSONValue], String, DshGlyph, String)] = [
            ("bash", ["command": "echo\n  hello"], "Run", AppIcon.terminal, "echo hello"),
            ("pwsh", ["description": "  a\tb "], "Run", AppIcon.terminal, "a b"),
            ("job_output", ["name": " job\nresult "], "Run", AppIcon.terminal, "job result"),
            ("job_kill", ["path": " a\nb "], "Run", AppIcon.terminal, "a b"),
            ("read", ["file_path": "a\nb", "path": "other"], "Read", .fileText, "a\nb"),
            ("read_image", ["path": "image.png"], "Read", .fileText, "image.png"),
            ("write", ["path": "output"], "Write", AppIcon.edit, "output"),
            ("edit", ["file_path": "source"], "Edit", AppIcon.edit, "source"),
            ("str_replace_editor", ["path": "source"], "Edit", AppIcon.edit, "source"),
            ("grep", ["pattern": "a.*b", "path": "/work"], "Search", AppIcon.search, "a.*b · /work"),
            ("grep", ["pattern": "match", "path": ""], "Search", AppIcon.search, "match"),
            ("glob", ["pattern": "**/*.swift", "path": "/ignored"], "Search", AppIcon.search, "**/*.swift"),
            ("web_fetch", ["url": "https://example.test/path"], "Web", .globeHemisphereWest, "example.test/path"),
            ("web_search", ["query": "a\nb"], "Web", .globeHemisphereWest, "a\nb"),
            ("mcp__phone__notify", ["kind": "alert", "title": "other"], "Phone", .deviceMobile, "alert"),
            ("mcp__phone__open", ["app": "Calendar"], "Phone", .deviceMobile, "Calendar"),
            ("custom", ["command": "", "file_path": " a\nb ", "name": "other"], "custom", AppIcon.tool, "a b"),
            ("", [:], "Tool", AppIcon.tool, ""),
        ]
        for (name, args, label, glyph, summary) in cases {
            let tool = ToolRow(id: "test", name: name, arguments: "", result: nil)
            let presentation = ToolPresenterRegistry.present(tool, args: args, theme: DesignTheme())
            #expect(presentation.style.label == label)
            #expect(presentation.style.glyph == glyph)
            #expect(presentation.summary == summary)
        }
    }

    @Test func debugRegistriesKeepExistingCommandNames() {
        #expect(Set(DebugPageRegistry.pages.keys).isSuperset(of: [
            "chat", "drawer",
            "settings", "notifications", "appearance", "language", "privacy", "diagnostics", "reply-preferences", "engine-parameters",
            "schedules", "usage", "agents", "files", "changes", "workspaces", "capabilities", "account", "providers", "model",
            "permissions", "phone", "pet", "about", "engine", "key", "remote", "welcome", "setup",
        ]))
        #expect(Set(FeatureSmokeRegistry.cases.keys) == Set(["t1", "t2", "t3", "t4", "t5", "t6", "t7", "t8", "t10", "t11", "t12", "t13", "t14", "t15", "store"]))
    }
}
