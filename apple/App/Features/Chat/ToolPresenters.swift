// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/lib/ui/chat/{tool_view,run_info}.dart.
import DSHClient
import SwiftUI

struct ToolStyle {
    let label: String
    let glyph: DshGlyph
    var tint: Color = DS.inkMuted
    var fill: Color = DS.surfaceHigh
}

struct ToolCardPresentation {
    let style: ToolStyle
    let summary: String
}

/// Tool families differ in both their visual identity and argument summaries.
protocol ToolPresenter {
    func matches(_ name: String) -> Bool
    func present(_ tool: ToolRow, args: [String: JSONValue], theme: DesignTheme) -> ToolCardPresentation
}

enum ToolPresenterRegistry {
    static let presenters: [any ToolPresenter] = [
        TerminalToolPresenter(),
        ReadToolPresenter(),
        WriteToolPresenter(names: ["write"], label: "Write"),
        WriteToolPresenter(names: ["edit", "str_replace_editor"], label: "Edit"),
        SearchToolPresenter(),
        WebToolPresenter(),
        TodoToolPresenter(),
        PhoneToolPresenter(),
    ]
    static func present(_ tool: ToolRow, args: [String: JSONValue], theme: DesignTheme) -> ToolCardPresentation {
        let presenter = presenters.first { $0.matches(tool.name) } ?? DefaultToolPresenter()
        return presenter.present(tool, args: args, theme: theme)
    }
}

struct TerminalToolPresenter: ToolPresenter {
    func matches(_ name: String) -> Bool { ["bash", "pwsh", "job_output", "job_kill"].contains(name) }
    func present(_ tool: ToolRow, args: [String: JSONValue], theme: DesignTheme) -> ToolCardPresentation {
        let summary = ["bash", "pwsh"].contains(tool.name)
            ? toolOneLine(args["command"]?.string ?? args["description"]?.string ?? "")
            : DefaultToolPresenter.summary(args)
        return ToolCardPresentation(style: ToolStyle(label: "Run", glyph: AppIcon.terminal), summary: summary)
    }
}

struct ReadToolPresenter: ToolPresenter {
    func matches(_ name: String) -> Bool { ["read", "read_image"].contains(name) }
    func present(_ tool: ToolRow, args: [String: JSONValue], theme: DesignTheme) -> ToolCardPresentation {
        ToolCardPresentation(style: ToolStyle(label: "Read", glyph: .fileText, tint: theme.accent, fill: theme.accentContainer),
                         summary: toolDisplayPath(args))
    }
}

struct WriteToolPresenter: ToolPresenter {
    let names: Set<String>
    let label: String
    func matches(_ name: String) -> Bool { names.contains(name) }
    func present(_ tool: ToolRow, args: [String: JSONValue], theme: DesignTheme) -> ToolCardPresentation {
        if tool.family == .read { return ReadToolPresenter().present(tool, args: args, theme: theme) }
        let verb = args["command"]?.string == "create" ? "Write" : label
        return ToolCardPresentation(style: ToolStyle(label: verb, glyph: AppIcon.edit, tint: DS.warn, fill: DS.warnContainer),
                                    summary: toolDisplayPath(args))
    }
}

struct SearchToolPresenter: ToolPresenter {
    func matches(_ name: String) -> Bool { ["grep", "glob"].contains(name) }
    func present(_ tool: ToolRow, args: [String: JSONValue], theme: DesignTheme) -> ToolCardPresentation {
        var summary = args["pattern"]?.string ?? ""
        let path = toolDisplayPath(args)
        if tool.name == "grep", !path.isEmpty { summary += " · " + path }
        return ToolCardPresentation(style: ToolStyle(label: "Search", glyph: AppIcon.search, tint: DS.dusk, fill: DS.duskContainer), summary: summary)
    }
}

struct WebToolPresenter: ToolPresenter {
    func matches(_ name: String) -> Bool { ["web_fetch", "web_search"].contains(name) }
    func present(_ tool: ToolRow, args: [String: JSONValue], theme: DesignTheme) -> ToolCardPresentation {
        let summary = tool.name == "web_fetch"
            ? (args["url"]?.string ?? "").replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression)
            : args["query"]?.string ?? ""
        return ToolCardPresentation(style: ToolStyle(label: "Web", glyph: .globeHemisphereWest, tint: theme.accent, fill: theme.accentContainer), summary: summary)
    }
}

struct TodoToolPresenter: ToolPresenter {
    func matches(_ name: String) -> Bool { name == "todo_write" }
    func present(_ tool: ToolRow, args: [String: JSONValue], theme: DesignTheme) -> ToolCardPresentation {
        let count = args["todos"]?.array?.count
        return ToolCardPresentation(style: ToolStyle(label: "Update to-dos", glyph: AppIcon.todo, tint: DS.success, fill: DS.successContainer),
                                    summary: count.map { String(localized: "\($0) items") } ?? "")
    }
}

struct PhoneToolPresenter: ToolPresenter {
    func matches(_ name: String) -> Bool { name.hasPrefix("mcp__phone__") }
    func present(_ tool: ToolRow, args: [String: JSONValue], theme: DesignTheme) -> ToolCardPresentation {
        ToolCardPresentation(style: ToolStyle(label: "Phone", glyph: .deviceMobile, tint: DS.success, fill: DS.successContainer),
                         summary: args["kind"]?.string ?? args["title"]?.string ?? args["app"]?.string ?? "")
    }
}

struct DefaultToolPresenter: ToolPresenter {
    func matches(_ name: String) -> Bool { true }
    func present(_ tool: ToolRow, args: [String: JSONValue], theme: DesignTheme) -> ToolCardPresentation {
        ToolCardPresentation(style: ToolStyle(label: tool.name.isEmpty ? "Tool" : tool.name, glyph: AppIcon.tool), summary: Self.summary(args))
    }
    static func summary(_ args: [String: JSONValue]) -> String {
        for key in ["command", "file_path", "path", "pattern", "query", "url", "name"] {
            if let value = args[key]?.string, !value.isEmpty { return toolOneLine(value) }
        }
        return ""
    }
}

private func toolOneLine(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }


private func toolDisplayPath(_ args: [String: JSONValue]) -> String {
    let path = args["file_path"]?.string ?? args["path"]?.string ?? ""
    let prefix = "/root/workspace/"
    return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
}
