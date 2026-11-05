// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/lib/ui/chat/{diff_page,render/diff_view}.dart.
import DSHClient
import SwiftUI

struct TurnDiffPage: View {
    let files: [TurnFileChange]
    @Binding var wraps: Bool
    @State private var index: Int
    @State private var notice: String?
    @State private var copies = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.designTheme) private var theme
    @Environment(\.appReduceMotion) private var reduceMotion

    init(files: [TurnFileChange], initialIndex: Int, wraps: Binding<Bool>) {
        self.files = files
        _index = State(initialValue: initialIndex)
        _wraps = wraps
    }

    var body: some View {
        VStack(spacing: Space.xs) {
            if files.indices.contains(index) {
                let file = files[index]
                header(file)
                if files.count > 1 { chips }
                TabView(selection: $index) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { offset, change in
                        FileDiffPane(file: change, wraps: wraps) {
                            copy(change.path, message: String(localized: "Path copied"))
                        }
                        .tag(offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .background { AppBackdrop() }
        .overlay(alignment: .bottom) { BriefNotice(text: $notice).padding(Space.lg) }
        .sensoryFeedback(.selection, trigger: index)
        .sensoryFeedback(.impact(weight: .light), trigger: copies)
    }

    private func header(_ file: TurnFileChange) -> some View {
        HStack(spacing: Space.sm) {
            GlassIconButton(glyph: AppIcon.back, label: "Back", size: 44) { dismiss() }
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Changes this turn").type(.titleMedium).foregroundStyle(DS.ink)
                HStack(spacing: Space.xs) {
                    Text("\(files.count) files").type(.bodySmall).foregroundStyle(DS.inkFaint)
                    DiffCounts(files: files)
                }
            }
            Spacer(minLength: 0)
            Button { wraps.toggle() } label: {
                Glyph(glyph: AppIcon.wrapLines, size: 21)
                    .foregroundStyle(theme.accent)
                    .frame(width: 44, height: 44)
                    .background(wraps ? theme.accentContainer : DS.secondaryContainer, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(wraps ? "Turn off line wrapping" : "Wrap lines"))
            GlassIconButton(glyph: AppIcon.copy, label: "Copy patch", size: 44) {
                copy(file.patch, message: String(localized: "Patch copied"))
            }
        }
        .padding(.horizontal, Space.md)
        .frame(minHeight: RunLayout.pageBarHeight)
    }

    private var chips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Space.sm) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { offset, file in
                        Button { withAnimation(reduceMotion ? nil : AppMotion.standard) { index = offset } } label: {
                            HStack(spacing: Space.xs) {
                                Text(verbatim: file.fileName).type(.labelMedium)
                                DiffCounts(added: file.added, removed: file.removed)
                            }
                            .foregroundStyle(index == offset ? theme.onAccentContainer : DS.ink)
                            .padding(.horizontal, Space.md)
                            .frame(minHeight: RunLayout.fileChipHeight)
                            .background(index == offset ? theme.accentContainer : DS.secondaryContainer, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(index == offset ? .isSelected : [])
                        .id(offset)
                    }
                }
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.xs)
            }
            .scrollIndicators(.hidden)
            .onChange(of: index, initial: true) { withAnimation(reduceMotion ? nil : AppMotion.standard) { proxy.scrollTo(index, anchor: .center) } }
        }
    }

    private func copy(_ text: String, message: String) {
        UIPasteboard.general.string = text
        notice = message
        copies += 1
    }
}

private struct FileDiffPane: View {
    let file: TurnFileChange
    let wraps: Bool
    let copyPath: () -> Void
    @Environment(\.designTheme) private var theme

    var body: some View {
        GeometryReader { geometry in
            let viewport = max(0, geometry.size.width - 2 * Space.lg)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.md) {
                    fileHeader
                    if file.hunks.allSatisfy({ $0.lines.isEmpty }) {
                        Text("No diff to display").type(.bodyMedium).foregroundStyle(DS.inkFaint)
                    } else if wraps {
                        well.frame(width: viewport)
                    } else {
                        ScrollView(.horizontal) {
                            well.frame(minWidth: viewport, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.lg)
                .padding(.bottom, Space.xxl)
            }
        }
    }

    private var fileHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: file.fileName).type(.titleMedium).foregroundStyle(DS.ink)
                if !file.directory.isEmpty {
                    Text(verbatim: file.directory).font(Mono.font(RunLayout.diffFontSize)).foregroundStyle(DS.inkMuted)
                }
                HStack(spacing: Space.sm) {
                    if file.created { Text("New file").type(.labelMedium).foregroundStyle(DS.success) }
                    DiffCounts(added: file.added, removed: file.removed)
                    if file.edits > 1 { Text("Edited \(file.edits) times").type(.bodySmall).foregroundStyle(DS.inkFaint) }
                }
            }
            Spacer(minLength: Space.sm)
            Button(action: copyPath) {
                HStack(spacing: Space.xs) {
                    Image(systemName: "link").accessibilityHidden(true)
                    Text("Copy path").type(.label)
                }.foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Space.sm)
    }

    private var well: some View {
        let hasOld = file.hunks.contains { $0.oldStart != nil }
        let hasNew = file.hunks.contains { $0.newStart != nil }
        let maxLine = file.hunks.reduce(1) { max($0, $1.oldStart ?? 0, $1.newStart ?? 0) }
        let longestHunk = file.hunks.map { $0.lines.count }.max() ?? 0
        let digits = String(maxLine + min(Int.max - maxLine, longestHunk)).count
        let width = CGFloat(digits) * RunLayout.diffNumberSize * 0.6 + 10
        let rows = diffRows()
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                switch row {
                case .header(let title):
                    Text(verbatim: title)
                        .font(Mono.font(11.5))
                        .foregroundStyle(DS.inkMuted)
                        .padding(.leading, width * CGFloat((hasOld ? 1 : 0) + (hasNew ? 1 : 0)) + Space.sm)
                        .padding(.vertical, Space.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background { Rectangle().fill(DS.codeWellHeader) }
                case .line(let text, let old, let new):
                    line(text, old: old, new: new, hasOld: hasOld, hasNew: hasNew, width: width)
                }
            }
        }
        .padding(.vertical, Space.sm)
        .background(DS.codeWell, in: RoundedRectangle(cornerRadius: Radius.md))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .textSelection(.enabled)
    }

    private func line(_ text: String, old: Int?, new: Int?, hasOld: Bool, hasNew: Bool, width: CGFloat) -> some View {
        let add = text.hasPrefix("+"), remove = text.hasPrefix("-")
        let ink = add ? DS.diffAddInk : remove ? DS.diffDeleteInk : DS.ink
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            if hasOld { number(old, width: width) }
            if hasNew { number(new, width: width) }
            Text(verbatim: add ? "+" : remove ? "−" : " ").frame(width: Space.xl)
                .accessibilityHidden(true)
            Text(verbatim: text.count > 1 ? String(text.dropFirst()) : " ")
                .fixedSize(horizontal: !wraps, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(Mono.font(RunLayout.diffFontSize, scale: theme.readingScale))
        .foregroundStyle(ink)
        .frame(minHeight: RunLayout.diffLineHeight * theme.readingScale, alignment: .topLeading)
        .padding(.trailing, Space.md)
        .background { Rectangle().fill(add ? DS.diffAddFill : remove ? DS.diffDeleteFill : Color.clear) }
    }

    private func number(_ value: Int?, width: CGFloat) -> some View {
        Text(verbatim: value.map(String.init) ?? "")
            .font(Mono.font(RunLayout.diffNumberSize))
            .foregroundStyle(DS.lineNumber)
            .frame(width: width, alignment: .trailing)
            .accessibilityHidden(true)
    }

    private enum Row {
        case header(String)
        case line(String, old: Int?, new: Int?)
    }

    private func diffRows() -> [Row] {
        let hunksByEdit = Dictionary(grouping: file.hunks, by: \.edit)
        var seen: [Int: Int] = [:]
        var rows: [Row] = []
        for hunk in file.hunks {
            seen[hunk.edit, default: 0] += 1
            var labels: [String] = []
            if file.edits > 1 { labels.append(String(localized: "Edit \(hunk.edit)")) }
            if (hunksByEdit[hunk.edit]?.count ?? 0) > 1 {
                labels.append(String(localized: "Hunk \(seen[hunk.edit, default: 1])"))
            }
            if let start = hunk.newStart, !file.created { labels.append(String(localized: "From line \(start)")) }
            if !labels.isEmpty { rows.append(.header(labels.joined(separator: " · "))) }
            else if !rows.isEmpty { rows.append(.header("…")) }
            var old = hunk.oldStart, new = hunk.newStart
            for text in hunk.lines {
                let add = text.hasPrefix("+"), remove = text.hasPrefix("-")
                rows.append(.line(text, old: add ? nil : old, new: remove ? nil : new))
                if !add { old = old.flatMap { $0 < Int.max ? $0 + 1 : nil } }
                if !remove { new = new.flatMap { $0 < Int.max ? $0 + 1 : nil } }
            }
        }
        return rows
    }
}
