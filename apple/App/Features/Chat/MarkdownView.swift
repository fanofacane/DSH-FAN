// SPDX-License-Identifier: AGPL-3.0-or-later
// Small block-level Markdown renderer for model replies. Inline syntax (bold,
// italic, code, links, strikethrough) uses Foundation's AttributedString.
// Tolerates partial input while streaming (e.g. an unclosed code fence).
import SwiftUI
import UIKit

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case image(alt: String, url: String)
    case code(language: String, text: String)
    case quote(String)
    case listItem(ordered: Bool, marker: String, depth: Int, text: String)
    case table(header: [String], rows: [[String]])
    case rule
}

enum MarkdownParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var i = 0
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Fenced code (``` or ~~~); an unclosed fence runs to the end.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                let fence = String(trimmed.prefix(3))
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[i]); i += 1
                }
                blocks.append(.code(language: language, text: code.joined(separator: "\n")))
                i += 1
                continue
            }
            if let image = imageLine(trimmed) {
                flush(); blocks.append(.image(alt: image.0, url: image.1)); i += 1; continue
            }
            if trimmed.isEmpty { flush(); i += 1; continue }
            if let heading = headingLevel(trimmed) {
                flush()
                blocks.append(.heading(level: heading, text: String(trimmed.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
                i += 1; continue
            }
            if ["---", "***", "___"].contains(trimmed.replacingOccurrences(of: " ", with: "")) && paragraph.isEmpty {
                blocks.append(.rule); i += 1; continue
            }
            if trimmed.hasPrefix(">") {
                flush()
                var quote: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.quote(quote.joined(separator: "\n")))
                continue
            }
            if let item = listItem(line) {
                flush(); blocks.append(item); i += 1; continue
            }
            if trimmed.contains("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flush()
                let header = cells(trimmed)
                var rows: [[String]] = []
                i += 2
                while i < lines.count, lines[i].contains("|"), !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(cells(lines[i])); i += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }
            paragraph.append(line); i += 1
        }
        flush()
        return blocks
    }

    private static func imageLine(_ line: String) -> (String, String)? {
        guard line.hasPrefix("!["), let divider = line.range(of: "]("), line.hasSuffix(")") else { return nil }
        return (String(line[line.index(line.startIndex, offsetBy: 2)..<divider.lowerBound]),
                String(line[divider.upperBound..<line.index(before: line.endIndex)]))
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func listItem(_ line: String) -> MarkdownBlock? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let body = line.drop { $0 == " " || $0 == "\t" }
        for bullet in ["- ", "* ", "+ "] where body.hasPrefix(bullet) {
            var text = String(body.dropFirst(2))
            var marker = "•"
            if text.hasPrefix("[ ] ") { marker = "☐"; text.removeFirst(4) }
            else if text.lowercased().hasPrefix("[x] ") { marker = "☑"; text.removeFirst(4) }
            return .listItem(ordered: false, marker: marker, depth: indent / 2, text: text)
        }
        let digits = body.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 3 {
            let rest = body.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                return .listItem(ordered: true, marker: digits + ".", depth: indent / 2, text: String(rest.dropFirst(2)))
            }
        }
        return nil
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-"), trimmed.contains("|") || trimmed.hasPrefix("-") else { return false }
        return trimmed.allSatisfy { "|-: ".contains($0) }
    }

    private static func cells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func inline(_ text: String, theme: DesignTheme) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        var value = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        // Inline code in JetBrains Mono, one step quieter than the body (as in Flutter).
        for run in value.runs where run.inlinePresentationIntent?.contains(.code) == true {
            value[run.range].font = Mono.font(14, scale: theme.readingScale)
            value[run.range].foregroundColor = DS.inkMuted
        }
        for run in value.runs where run.link != nil { value[run.range].foregroundColor = theme.accent }
        return value
    }
}

struct MarkdownView: View {
    @Environment(AppSession.self) private var chat
    @State private var artifact: ArtifactDestination?
    let source: String
    var body: some View {
        let blocks = MarkdownParser.parse(source)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
        .foregroundStyle(DS.ink)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == nil || ["file", "sandbox"].contains(url.scheme ?? ""), let session = chat.transcript.currentSessionId {
                artifact = ArtifactDestination(sessionId: session, path: url.scheme == nil ? url.relativeString : url.path)
                return .handled
            }
            return .systemAction
        })
        .sheet(item: $artifact) { file in NavigationStack { FilePreviewPage(sessionId: file.sessionId, path: file.path) } }
        // No inline selection: long press opens the message menu ("Select text").
    }
}

private struct MarkdownBlockView: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownParser.inline(text, theme: theme))
                .type(level == 1 ? .headline : level == 2 ? .title : .titleMedium)
                .padding(.top, 4)
        case .image(let alt, let source):
            if let url = URL(string: source), url.scheme == "https" {
                MessagePhoto(source: .web(url)).accessibilityLabel(Text(verbatim: alt))
            } else if let session = chat.transcript.currentSessionId {
                MessagePhoto(source: .workspace(URL(string: source)?.scheme == "file" || URL(string: source)?.scheme == "sandbox" ? URL(string: source)?.path ?? source : source, session))
                    .accessibilityLabel(Text(verbatim: alt))
            }
        case .paragraph(let text):
            Text(MarkdownParser.inline(text, theme: theme)).type(.body)
        case .code(let language, let text):
            CodeBlockView(language: language, code: text)
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5).fill(DS.rule).frame(width: 3)
                Text(MarkdownParser.inline(text, theme: theme)).type(.body).foregroundStyle(DS.inkMuted)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .listItem(_, let marker, let depth, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker).type(.body).foregroundStyle(DS.inkMuted).monospacedDigit()
                Text(MarkdownParser.inline(text, theme: theme)).type(.body)
            }
            .padding(.leading, CGFloat(depth) * 16)
        case .table(let header, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow { ForEach(Array(header.enumerated()), id: \.offset) { Text(MarkdownParser.inline($1, theme: theme)).type(.titleSmall) } }
                    Divider().overlay(DS.rule)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow { ForEach(Array(row.enumerated()), id: \.offset) { Text(MarkdownParser.inline($1, theme: theme)).type(.bodyMedium) } }
                    }
                }
                .padding(12)
            }
            .background(DS.codeWell, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(DS.codeWellBorder))
        case .rule:
            Divider().overlay(DS.rule)
        }
    }
}

/// Code well (render/code_block): header with language, wrap and copy; JetBrains Mono body.
struct CodeBlockView: View {
    @Environment(\.designTheme) private var theme
    let language: String
    let code: String
    @State private var copied = false
    @State private var wrap = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Text(language.isEmpty ? "code" : language).font(Mono.font(12, scale: theme.readingScale)).foregroundStyle(DS.inkFaint)
                Spacer()
                Button { wrap.toggle() } label: { Glyph(glyph: AppIcon.wrapLines, size: 16) }
                    .foregroundStyle(wrap ? theme.accent : DS.inkFaint)
                    .accessibilityLabel(Text("Wrap lines"))
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = false }
                } label: {
                    HStack(spacing: 4) {
                        Glyph(glyph: copied ? DshGlyph.check : AppIcon.copy, size: 14)
                        Text(copied ? "Copied" : "Copy").font(.system(size: 12))
                    }
                }
                .foregroundStyle(DS.inkFaint)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(DS.codeWellHeader)
            Group {
                if wrap {
                    codeText.fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) { codeText }
                }
            }
        }
        .background(DS.codeWell)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(DS.codeWellBorder))
    }

    private var codeText: some View {
        Text(code)
            .font(Mono.font(13, scale: theme.readingScale))
            .lineSpacing(13 * 0.35)
            .foregroundStyle(DS.ink)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ArtifactDestination: Identifiable {
    let id = UUID()
    let sessionId: String
    let path: String
}
