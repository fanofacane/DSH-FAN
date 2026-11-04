// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import SwiftUI

struct ComposerPalette: View {
    @Environment(AppSession.self) private var chat
    @Binding var text: String
    @State private var rows: [CompletionCandidate] = []
    @State private var error: String?
    @State private var loading = false
    private var isCommand: Bool { text.hasPrefix("/") && !text.contains(where: \.isWhitespace) }
    private var mentionRange: Range<String.Index>? { ComposerCompletion.fileRange(in: text) }
    private var visible: Bool { isCommand || mentionRange != nil }
    var body: some View {
        if visible {
            VStack(alignment: .leading, spacing: 4) {
                Text(isCommand ? "Commands" : "Workspace files").type(.eyebrow).foregroundStyle(DS.inkFaint)
                if loading { ProgressView() }
                if let error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger) }
                if !loading && rows.isEmpty && error == nil { Text("No matches").type(.bodySmall).foregroundStyle(DS.inkFaint) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            Button { pick(row) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isCommand ? "command" : row.kind == "directory" ? "folder" : "doc")
                                    VStack(alignment: .leading) {
                                        Text(verbatim: isCommand ? "/" + (row.name ?? "") : row.path ?? "")
                                            .type(.bodyMedium).lineLimit(1)
                                        if isCommand, let description = row.description {
                                            Text(verbatim: commandDescription(row.name ?? "", fallback: description)).type(.bodySmall).foregroundStyle(DS.inkFaint).lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                }.foregroundStyle(DS.ink).padding(.vertical, 8).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxHeight: 180)
            }.padding(12).glass(.card, radius: Radius.lg)
            .task(id: text + (chat.transcript.currentSessionId ?? "")) { await load() }
        }
    }
    private func commandDescription(_ name: String, fallback: String) -> String {
        switch name {
        case "compact": String(localized: "Compact older conversation history")
        case "goal": String(localized: "Set or view the long-running goal")
        case "permission": String(localized: "Switch the permission preset")
        case "plan": String(localized: "Review or change planning mode")
        case "features": String(localized: "View engine features")
        default: fallback
        }
    }
    private func load() async {
        let input = text
        loading = true; rows = []; error = nil
        do {
            try await Task.sleep(nanoseconds: 180_000_000)
            let id = try await chat.transcript.ensureSession()
            let all: [CompletionCandidate]
            if isCommand {
                all = try await chat.connection.commandsAPI.list(agentId: id).map(CompletionCandidate.command)
            } else if let range = mentionRange {
                var query = String(text[range].dropFirst())
                if query.hasPrefix("\"") { query.removeFirst() }
                all = try await (chat.connection.filesAPI.listReferences(agentId: id, query: query) ?? []).map(CompletionCandidate.file)
            } else { return }
            try Task.checkCancellation()
            guard input == text else { return }
            if isCommand {
                let query = String(text.dropFirst()).lowercased()
                rows = all.filter { row in
                    guard let name = row.name else { return false }
                    return ComposerCompletion.commandAllowed(name) && name.lowercased().hasPrefix(query)
                }
            } else { rows = all.filter { ComposerCompletion.mention(path: $0.path ?? "", directory: $0.kind == "directory") != nil } }
        } catch is CancellationError { return }
        catch { if !Task.isCancelled { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" } }
        if !Task.isCancelled { loading = false }
    }
    private func pick(_ row: CompletionCandidate) {
        if isCommand, let name = row.name {
            text = "/" + name + " "
            if !row.acceptsInput {
                let line = text; text = ""
                Task { await chat.transcript.executeCommand(line) }
            }
        } else if let range = mentionRange, let path = row.path,
                  let mention = ComposerCompletion.mention(path: path, directory: row.kind == "directory") {
            text.replaceSubrange(range, with: mention + (row.kind == "directory" ? "" : " "))
        }
    }
}

private enum CompletionCandidate {
    case command(CommandEntry), file(FileReference)
    var name: String? { if case .command(let v) = self { v.name } else { nil } }
    var description: String? { if case .command(let v) = self { v.description } else { nil } }
    var acceptsInput: Bool { if case .command(let v) = self { v.acceptsInput } else { false } }
    var path: String? { if case .file(let v) = self { v.path } else { nil } }
    var kind: String? { if case .file(let v) = self { v.kind } else { nil } }
}
