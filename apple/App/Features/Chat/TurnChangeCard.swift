// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/lib/ui/chat/widgets/change_card.dart.
import DSHClient
import SwiftUI

struct TurnChangeCard: View {
    let files: [TurnFileChange]
    let open: (Int) -> Void
    @Environment(\.designTheme) private var theme
    @State private var notice: String?
    @State private var copies = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.sm) {
                Glyph(glyph: AppIcon.diff, size: 20).foregroundStyle(DS.inkMuted)
                Text("Changed \(files.count) files").type(.titleSmall).foregroundStyle(DS.ink)
                Spacer(minLength: 0)
                if files.count > 1 { DiffCounts(files: files) }
            }
            .padding(.horizontal, Space.lg)
            .frame(minHeight: RunLayout.fileRowHeight)
            ForEach(Array(files.prefix(3).enumerated()), id: \.element.id) { index, file in
                Button { open(index) } label: {
                    HStack(spacing: Space.sm) {
                        Glyph(glyph: file.created ? AppIcon.fileNew : AppIcon.document, size: 20)
                            .foregroundStyle(file.created ? DS.success : DS.inkFaint)
                        Text(verbatim: file.fileName).type(.bodyMedium).foregroundStyle(DS.ink)
                            .layoutPriority(1)
                        if file.created {
                            Text("New").type(.labelSmall).foregroundStyle(DS.success).fixedSize()
                        }
                        if !file.directory.isEmpty {
                            Text(verbatim: file.directory).font(Mono.font(11.5)).foregroundStyle(DS.inkFaint)
                        }
                        Spacer(minLength: 0)
                        DiffCounts(added: file.added, removed: file.removed)
                    }
                    .lineLimit(1)
                    .padding(.horizontal, Space.lg)
                    .frame(minHeight: RunLayout.fileRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Copy path", systemImage: "link") {
                        UIPasteboard.general.string = file.path
                        notice = String(localized: "Path copied")
                        copies += 1
                    }
                }
            }
            Button { open(0) } label: {
                HStack(spacing: Space.sm) {
                    Text("View changes").type(.label).foregroundStyle(theme.accent)
                    Spacer()
                    if files.count > 3 {
                        Text("\(files.count - 3) more files").type(.bodySmall).foregroundStyle(DS.inkFaint)
                    }
                    Glyph(glyph: AppIcon.disclosure, size: 18).foregroundStyle(DS.inkFaint)
                }
                .padding(.horizontal, Space.lg)
                .frame(minHeight: RunLayout.fileRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            BriefNotice(text: $notice)
        }
        .padding(.vertical, Space.xs)
        .glass(.card, radius: Radius.lg)
        .sensoryFeedback(.selection, trigger: copies)
    }
}

struct DiffCounts: View {
    let added: Int
    let removed: Int

    init(added: Int, removed: Int) {
        self.added = added
        self.removed = removed
    }

    init(files: [TurnFileChange]) {
        added = files.reduce(0) { $0 + $1.added }
        removed = files.reduce(0) { $0 + $1.removed }
    }

    var body: some View {
        HStack(spacing: Space.xs) {
            if added > 0 || removed == 0 {
                Text(verbatim: "+\(added)").foregroundStyle(DS.success)
            }
            if removed > 0 {
                Text(verbatim: "−\(removed)").foregroundStyle(DS.danger)
            }
        }
        .font(Mono.font(12, weight: .medium))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(added) added, \(removed) removed"))
    }
}
