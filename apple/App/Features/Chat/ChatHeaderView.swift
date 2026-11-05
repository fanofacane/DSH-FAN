// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/lib/ui/chat/chat_screen.dart.
import DSHClient
import SwiftUI

struct ChatHeaderView: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    @Environment(HostStore.self) private var hosts
    let openDrawer: () -> Void
    @Binding var files: Bool
    @Binding var agents: Bool
    @Binding var schedules: Bool
    let openUsage: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            GlassIconButton(glyph: AppIcon.menu, label: "Chats", action: openDrawer)
            titlePill
            Spacer(minLength: 0)
            modelPill
            Menu {
                Button("Files") { files = true }
                Button("Agent presets") { agents = true }
                Button("Usage and run info", action: openUsage)
                Button("Scheduled tasks") { schedules = true }
            } label: { Image(systemName: "ellipsis").frame(width: 36, height: 40).foregroundStyle(DS.ink) }
                .accessibilityLabel(Text("Chat tools"))
            if !chat.transcript.items.isEmpty {
                GlassIconButton(glyph: AppIcon.newChat, label: "New chat") { chat.transcript.newChat() }
                    .disabled(chat.transcript.busy)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(alignment: .top) {
            // Top fade so text scrolls under the floating chrome (TopFade), from the
            // screen edge through the status bar.
            LinearGradient(stops: [.init(color: DS.backdropTop, location: 0), .init(color: DS.backdropTop, location: 0.55),
                                   .init(color: DS.backdropTop.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: 128)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }

    private var titlePill: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hugs short titles; shrinks with an ellipsis when the header runs out of room.
            Text(Self.clip(chat.transcript.currentTitle ?? String(localized: "New chat")))
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
                .lineLimit(1).truncationMode(.tail)
            HStack(spacing: 5) {
                Circle().fill(status.color).frame(width: 6, height: 6)
                Text(status.text).font(.system(size: 11)).foregroundStyle(status.textColor)
            }
        }
        .padding(.leading, 16).padding(.trailing, 18).padding(.vertical, 4)
        .frame(height: 40)
        .glassCapsule()
        .layoutPriority(0)
        .animation(.snappy, value: chat.transcript.currentTitle)
    }

    private var status: (text: LocalizedStringKey, color: Color, textColor: Color) {
        if chat.requests.currentApproval != nil { return ("Waiting for you", DS.warn, DS.warn) }
        if chat.transcript.busy { return ("Generating", theme.accent, DS.inkFaint) }
        if let host = hosts.activeHost {
            return ("\(host.name)", chat.connection.state == .ready ? DS.success : hosts.state.color, DS.inkFaint)
        }
        return ("On device", DS.success, DS.inkFaint)
    }

    @ViewBuilder private var modelPill: some View {
        @Bindable var connection = chat.connection
        if let model = chat.connection.selectedModel {
            Menu {
                Picker("Model", selection: $connection.selectedModel) {
                    ForEach(chat.connection.models) { option in Text(option.name).tag(Optional(option)) }
                }
                if !model.efforts.isEmpty {
                    Picker("Thinking", selection: Binding(get: { chat.connection.effort(for: model) ?? model.efforts[0].id },
                                                          set: { chat.connection.setEffort($0, for: model) })) {
                        ForEach(model.efforts) { effort in Text(effortTitle(effort.id, effort.name)).tag(effort.id) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Glyph(glyph: AppIcon.model, size: 16).foregroundStyle(theme.accent)
                    Text(Self.shortName(model.name)).font(.system(size: 14, weight: .semibold)).foregroundStyle(DS.ink)
                        .lineLimit(1).fixedSize()
                    // Like Flutter: the effort shows on the empty screen only; in a chat the pill stays short.
                    if chat.transcript.items.isEmpty, let effort = chat.connection.effort(for: model), let option = model.efforts.first(where: { $0.id == effort }) {
                        Text("·").foregroundStyle(DS.inkGhost)
                        Text(effortTitle(option.id, option.name)).font(.system(size: 13)).foregroundStyle(DS.inkMuted)
                    }
                    Glyph(glyph: DshGlyph.caretDown, size: 14).foregroundStyle(DS.inkMuted)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .glassCapsule()
            }
            .disabled(chat.transcript.busy)
            .layoutPriority(1)
        }
    }

    /// The title pill hugs its text; long titles end in an ellipsis (~12 CJK characters).
    static func clip(_ title: String) -> String {
        var width = 0, result = ""
        for character in title {
            width += character.unicodeScalars.first.map { $0.value > 0x2E80 ? 2 : 1 } ?? 1
            if width > 22 { return result + "…" }
            result.append(character)
        }
        return result
    }

    /// 「DeepSeek-V4-Pro」→「V4 Pro」, as the Flutter model pill shows it.
    static func shortName(_ name: String) -> String {
        var value = name
        if value.lowercased().hasPrefix("deepseek-") { value.removeFirst("deepseek-".count) }
        return value.replacingOccurrences(of: "-", with: " ")
    }

    private func effortTitle(_ id: String, _ name: String) -> String {
        switch id {
        case "off": String(localized: "Off")
        case "low": String(localized: "Low")
        case "high": String(localized: "High")
        case "max": String(localized: "Max")
        default: name
        }
    }

}
