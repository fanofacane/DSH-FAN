// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import SwiftUI
extension ToolRow {
    var filePath: String? {
        let args = (try? JSONValue(data: Data(arguments.utf8)))?.object ?? [:]
        return args["file_path"]?.string ?? args["path"]?.string
    }
    var textChanges: [TextChange] {
        guard !failed, result != nil else { return [] }
        if !presentation.changes.isEmpty { return presentation.changes }
        let args = (try? JSONValue(data: Data(arguments.utf8)))?.object ?? [:]
        if name == "edit", let before = args["old_string"]?.string, let after = args["new_string"]?.string { return [TextChange(before: before, after: after)] }
        if name == "str_replace_editor", args["command"]?.string == "str_replace", let before = args["old_str"]?.string, let after = args["new_str"]?.string { return [TextChange(before: before, after: after)] }
        if name == "write", let after = args["content"]?.string { return [TextChange(before: nil, after: after)] }
        return []
    }
}
struct ChangesPage: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    private var tools: [ToolRow] {
        let items = chat.transcript.items
        let start = items.lastIndex { $0.role == .user } ?? 0
        return items.dropFirst(start).flatMap(\.tools).filter { !$0.textChanges.isEmpty && $0.filePath != nil }
    }
    var body: some View {
        SettingsPage(title: "Latest turn changes") {
            Text("Only changes reported by edit and write tools are shown.").type(.bodySmall).foregroundStyle(DS.inkFaint).padding(.bottom, 16)
            if tools.isEmpty { Text("No reported file changes").type(.bodyMedium).foregroundStyle(DS.inkMuted) }
            ForEach(tools) { tool in
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: tool.filePath ?? "").font(Mono.font(13, scale: theme.readingScale)).foregroundStyle(DS.ink)
                    Text("Change excerpts").type(.eyebrow).foregroundStyle(DS.inkFaint)
                    ForEach(Array(tool.textChanges.enumerated()), id: \.offset) { _, change in
                        if change.before == nil { Text("Previous content is unavailable.").type(.bodySmall).foregroundStyle(DS.inkFaint) }
                        ScrollView(.horizontal) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(change.lines.enumerated()), id: \.offset) { _, line in
                                    Text(verbatim: line).font(Mono.font(12, scale: theme.readingScale)).foregroundStyle(line.hasPrefix("+") ? DS.success : line.hasPrefix("-") ? DS.danger : DS.inkMuted)
                                        .textSelection(.enabled)
                                }
                            }.padding(10)
                        }.background(DS.codeWell, in: RoundedRectangle(cornerRadius: Radius.md))
                    }
                }.padding(12).glass(.card, radius: Radius.lg).padding(.bottom, 16)
            }
        }
    }
}
