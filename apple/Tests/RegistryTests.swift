// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import SwiftUI
import Testing
@testable import DSH

@MainActor struct RegistryTests {
    @Test func settingsKeepOrderAndLocalAccountBoundary() throws {
        let local = SettingsContext()
        #expect(SettingsRegistry.sections == [.ai, .connection, .abilities, .about])
        #expect(SettingsRegistry.entries(in: .ai, context: local).map(\.id) == ["reply-preferences", "agents", "account", "providers", "model", "permissions"])
        #expect(SettingsRegistry.entries(in: .connection, context: local).map(\.id) == ["workspaces", "remote"])
        #expect(SettingsRegistry.entries(in: .abilities, context: local).map(\.id) == ["notifications", "schedules", "capabilities", "phone", "pet"])
        #expect(SettingsRegistry.entries(in: .about, context: local).map(\.id) == ["appearance", "language", "privacy", "diagnostics", "engine-parameters", "about"])
        var remote = local; remote.isRemote = true
        let remoteAI = SettingsRegistry.entries(in: .ai, context: remote).map(\.id)
        #expect(remoteAI == ["reply-preferences", "agents", "providers", "model", "permissions"])
        #expect(Set(SettingsRegistry.entries.map(\.id)).count == SettingsRegistry.entries.count)
        let indented = SettingsRegistry.entries.filter { $0.dividerInset == 70 }.map(\.id)
        #expect(indented == ["model", "phone"])
    }

    @Test func settingsSubtitlesUseCurrentContext() throws {
        var context = SettingsContext(modelSubtitle: "model · effort", presetName: "preset", remoteSubtitle: "host", version: "1.2.3")
        func subtitle(_ id: String) throws -> String? {
            try #require(SettingsRegistry.entries.first { $0.id == id }).subtitle(context)
        }
        #expect(try subtitle("model") == "model · effort")
        #expect(try subtitle("permissions") == "preset")
        #expect(try subtitle("remote") == "host")
        #expect(try subtitle("about") == "1.2.3")
        #expect(try subtitle("phone") == String(localized: "Off"))
        context.phoneEnabled = true; context.petEnabled = true
        #expect(try subtitle("phone") == String(localized: "On"))
        #expect(try subtitle("pet") == String(localized: "Deepy the whale"))
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
        #expect(Set(DebugPageRegistry.pages.keys) == Set([
            "chat", "drawer",
            "settings", "notifications", "appearance", "language", "privacy", "diagnostics", "reply-preferences", "engine-parameters",
            "schedules", "usage", "agents", "files", "changes", "workspaces", "capabilities", "account", "providers", "model",
            "permissions", "phone", "pet", "about", "engine", "key", "remote", "welcome", "setup",
        ]))
        #expect(Set(FeatureSmokeRegistry.cases.keys) == Set(["t1", "t2", "t3", "t4", "t5", "t6", "t7", "t8", "t10", "t11", "t12", "t13", "t14", "t15", "store"]))
    }
}
