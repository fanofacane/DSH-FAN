// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/chat/dsh_ui/ (dsh-ui blocks and [dsh-ui reply]).
import Charts
import DSHClient
import SwiftUI

struct VisualReply: Identifiable {
    let id: String
    let kind: String
    let data: JSONValue
    let children: [VisualReply]

    static func decode(_ text: String) -> VisualReply? {
        guard text.utf8.count <= 4096,
              let value = try? JSONValue(data: Data(text.utf8)) else { return nil }
        return node(value, id: "root", depth: 0)
    }

    private static func node(_ value: JSONValue, id: String, depth: Int) -> VisualReply? {
        guard depth < 8, let kind = value["type"]?.string,
              ["stack", "row", "text", "metric", "chart", "compare", "steps", "callout", "options", "confirm"].contains(kind)
        else { return nil }
        let children = (value["children"]?.array ?? []).prefix(12).enumerated().compactMap { index, child in
            node(child, id: "\(id).\(index)", depth: depth + 1)
        }
        return VisualReply(id: id, kind: kind, data: value, children: children)
    }
}

struct VisualReplyView: View {
    let node: VisualReply
    @Environment(AppSession.self) private var chat
    @Environment(\.designTheme) private var theme
    @State private var selection: Set<Int> = []
    @State private var other = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if let title = node.data["title"]?.string { Text(verbatim: title).settingsType(.titleMedium) }
            switch node.kind {
            case "stack":
                ForEach(node.children) { VisualReplyView(node: $0) }
            case "row":
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Space.md) { ForEach(node.children) { VisualReplyView(node: $0) } }
                    VStack(alignment: .leading, spacing: Space.md) { ForEach(node.children) { VisualReplyView(node: $0) } }
                }
            case "metric":
                Text(verbatim: string("label")).settingsType(.bodyMedium).foregroundStyle(DS.inkMuted)
                Text(verbatim: string("value")).monospacedDigit().settingsType(.headline).foregroundStyle(tone)
            case "chart":
                chart
            case "compare":
                comparison
            case "steps":
                steps
            case "options":
                options
            case "confirm":
                actions
            default:
                Text(verbatim: string("text")).type(.bodyMedium).foregroundStyle(node.kind == "callout" ? tone : DS.ink)
            }
            if let caption = node.data["caption"]?.string {
                Text(verbatim: caption).settingsType(.bodySmall).foregroundStyle(DS.inkFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .glass(.card)
    }

    private func string(_ key: String) -> String { node.data[key]?.string ?? "" }
    private var tone: Color {
        switch string("tone") {
        case "good": DS.success
        case "warn": DS.warn
        case "bad": DS.danger
        case "info": DS.info
        default: theme.accent
        }
    }

    private struct Point: Identifiable {
        let id: Int
        let category: String
        let series: String
        let value: Double
    }

    private var points: [Point] {
        let labels = node.data["categories"]?.array ?? []
        let series = node.data["series"]?.array ?? []
        return series.prefix(6).enumerated().flatMap { index, group in
            (group["values"]?.array ?? []).prefix(60).enumerated().compactMap { offset, value in
                guard labels.indices.contains(offset), let category = labels[offset].string,
                      let value = value.double, value.isFinite, abs(value) <= 1e15 else { return nil }
                return Point(id: index * 60 + offset, category: category,
                             series: group["name"]?.string ?? String(index + 1), value: value)
            }
        }
    }

    private var chart: some View {
        Chart(points) { point in
            if string("kind") == "line" {
                LineMark(x: .value("Category", point.category), y: .value("Value", point.value))
                    .foregroundStyle(by: .value("Series", point.series))
            } else if string("kind") == "hbar" {
                BarMark(x: .value("Value", point.value), y: .value("Category", point.category))
                    .foregroundStyle(by: .value("Series", point.series))
            } else if string("kind") == "donut" {
                SectorMark(angle: .value("Value", max(0, point.value)), innerRadius: .ratio(0.55))
                    .foregroundStyle(by: .value("Category", point.category))
            } else {
                BarMark(x: .value("Category", point.category), y: .value("Value", point.value))
                    .foregroundStyle(by: .value("Series", point.series))
                    .position(by: .value("Series", point.series))
            }
        }
        .frame(height: 170)
        .accessibilityLabel(Text(verbatim: node.data["title"]?.string ?? String(localized: "Chart")))
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            ForEach(Array((node.data["items"]?.array ?? []).prefix(4).enumerated()), id: \.offset) { _, item in
                Text(verbatim: item["title"]?.string ?? "").settingsType(.titleSmall)
                ForEach(Array((item["rows"]?.array ?? []).prefix(12).enumerated()), id: \.offset) { _, row in
                    if let pair = row.array, pair.count == 2 {
                        InfoRow(label: LocalizedStringKey(pair[0].string ?? ""), value: pair[1].string ?? "")
                    }
                }
            }
        }
    }

    private var steps: some View {
        ForEach(Array((node.data["items"]?.array ?? []).prefix(12).enumerated()), id: \.offset) { _, item in
            let status = item["status"]?.string
            SettingsRow(glyph: status == "done" ? .check : status == "failed" ? .x : .circle,
                        tone: status == "failed" ? .danger : .neutral,
                        title: "", subtitle: item["detail"]?.string, verbatim: item["label"]?.string) { EmptyView() }
        }
    }

    private var choices: [String] {
        (node.data["options"]?.array ?? []).prefix(8).compactMap { $0["label"]?.string }
    }
    private var replyMarker: String? {
        guard let id = node.data["id"]?.string, !id.isEmpty, id.count <= 80, !id.contains(where: \.isNewline) else { return nil }
        return "[dsh-ui reply] " + id
    }
    private var canReply: Bool {
        guard let marker = replyMarker, chat.transcript.canSend else { return false }
        return !chat.transcript.items.contains { $0.role == .user && $0.text.split(whereSeparator: \.isNewline).first.map(String.init) == marker }
    }
    private var options: some View {
        let multi = node.data["multi"]?.bool == true
        let acceptsOther = node.data["freetext"]?.bool == true || node.data["freetext"]?.string != nil
        return VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(Array(choices.enumerated()), id: \.offset) { index, label in
                SettingsChoiceRow(title: label, selected: selection.contains(index)) {
                    if multi {
                        if !selection.insert(index).inserted { selection.remove(index) }
                    } else { selection = [index] }
                }
            }
            if acceptsOther { TextField("Other answer", text: $other).padding(Space.sm) }
            MistButton(title: "Send answer") {
                let values = selection.sorted().compactMap { choices.indices.contains($0) ? choices[$0] : nil }
                let chosen = values + (other.isEmpty ? [] : [String(other.prefix(300))])
                reply(chosen.joined(separator: ", "))
            }.disabled(!canReply || (selection.isEmpty && other.isEmpty))
        }
        .disabled(!canReply)
    }

    private var actions: some View {
        HStack {
            MistButton(title: LocalizedStringKey(node.data["confirmLabel"]?.string ?? "Confirm")) {
                reply(node.data["confirmLabel"]?.string ?? String(localized: "Confirm"))
            }
            MistButton(title: LocalizedStringKey(node.data["cancelLabel"]?.string ?? "Cancel"), kind: .secondary) {
                reply(node.data["cancelLabel"]?.string ?? String(localized: "Cancel"))
            }
        }
        .disabled(!canReply)
    }

    private func reply(_ text: String) {
        guard let marker = replyMarker, canReply else { return }
        Task { await chat.transcript.send(marker + "\n" + text) }
    }
}
