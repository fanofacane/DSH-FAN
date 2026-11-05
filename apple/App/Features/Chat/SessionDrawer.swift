// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import SwiftUI

struct SessionDrawer: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    @Environment(EngineModel.self) private var engine
    @Environment(HostStore.self) private var hosts
    let close: () -> Void
    let openSettings: () -> Void
    var openHosts: () -> Void = {}
    @State private var showHosts = false

    private var hostDot: Color {
        if hosts.isRemote { return chat.connection.state == .ready ? DS.success : hosts.state.color }
        return engine.status.phase == .running ? DS.success : DS.warn
    }

    private var hostLine: String {
        guard let host = hosts.activeHost else { return String(localized: engine.status.phase.titleResource) }
        if chat.connection.state == .ready { return host.connectedLabel }
        return hosts.state.label(host)
    }
    @State private var query = ""
    @AppStorage("chat.groupByWorkspace") private var groupByWorkspace = false
    @State private var renaming: SessionSummary?
    @State private var newTitle = ""
    @State private var deleting: SessionSummary?
    @State private var archiving: SessionSummary?
    @State private var showArchived = false
    @State private var sessionError: String?
    @State private var deleteError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                BrandMark(size: 30)
                Text(verbatim: "DSH Fan").font(.system(size: 20, weight: .semibold)).tracking(0.6).foregroundStyle(DS.ink)
                Spacer()
                Button { chat.transcript.newChat(); close() } label: {
                    HStack(spacing: 6) {
                        Glyph(glyph: AppIcon.newChat, size: 18)
                        Text("New chat").font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(DS.onAccent)
                    .padding(.horizontal, 14).frame(height: 38)
                    .background(theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)

            HStack(spacing: 8) {
                Glyph(glyph: AppIcon.search, size: 18).foregroundStyle(DS.inkFaint)
                TextField("Search chats", text: $query).type(.bodyMedium)
            }
            .padding(.horizontal, 14).frame(height: 40)
            .background(Color(light: 0xFFFFFFFF, lightAlpha: 0.6, dark: 0xFFFFFFFF, darkAlpha: 0.06), in: Capsule())

            Toggle("Archived chats", isOn: $showArchived).type(.bodySmall).tint(theme.accent)
            Toggle("Group by workspace", isOn: $groupByWorkspace).type(.bodySmall).tint(theme.accent)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if filtered.isEmpty {
                        Text(query.isEmpty ? "No chats yet" : "No matches").type(.bodyMedium).foregroundStyle(DS.inkFaint).padding(.top, 12)
                    }
                    if !pinnedSessions.isEmpty {
                        Text("Pinned").type(.eyebrow).foregroundStyle(DS.inkFaint).padding(.top, 14).padding(.leading, 8)
                        ForEach(pinnedSessions) { session in row(session) }
                    }
                    ForEach(groups, id: \.title) { group in
                        Text(group.title).type(.eyebrow).foregroundStyle(DS.inkFaint).padding(.top, 14).padding(.bottom, 4).padding(.leading, 8)
                        ForEach(group.sessions) { session in row(session) }
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 10) {
                // Host chip (host_switcher.dart): this phone or the remote host, tap to switch.
                Button { showHosts = true } label: {
                    HStack(spacing: 10) {
                        Glyph(glyph: hosts.isRemote ? AppIcon.computer : DshGlyph.deviceMobile, size: 20).foregroundStyle(theme.accent)
                            .frame(width: 40, height: 40).background(theme.accentContainer, in: Circle())
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 4) {
                                Text(verbatim: hosts.activeHost?.name ?? String(localized: "This phone"))
                                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink).lineLimit(1)
                                Glyph(glyph: AppIcon.dropdown, size: 14).foregroundStyle(DS.inkFaint)
                            }
                            HStack(spacing: 5) {
                                Circle().fill(hostDot).frame(width: 6, height: 6)
                                Text(verbatim: hostLine).font(.system(size: 12)).foregroundStyle(DS.inkFaint).lineLimit(1)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Switch host"))
                Spacer()
                GlassIconButton(glyph: AppIcon.settings, label: "Settings", action: openSettings)
            }
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            UnevenRoundedRectangle(cornerRadii: .init(bottomTrailing: Radius.xl, topTrailing: Radius.xl), style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(UnevenRoundedRectangle(cornerRadii: .init(bottomTrailing: Radius.xl, topTrailing: Radius.xl), style: .continuous)
                    .fill(Color(light: 0xFFF6F9FE, lightAlpha: 0.86, dark: 0xFF232832, darkAlpha: 0.9)))
                .shadow(color: DS.shadowInk.opacity(0.18), radius: 24, x: 8)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showHosts) { HostSwitcherSheet(manage: openHosts) }
        .alert("Could not update chat", isPresented: Binding(get: { sessionError != nil }, set: { if !$0 { sessionError = nil } })) {
            Button("OK") { sessionError = nil }
        } message: { Text("Request failed: \(sessionError ?? "E_WORKSPACE_RESPONSE")") }
        .confirmationDialog("Archive this chat?", isPresented: Binding(get: { archiving != nil }, set: { if !$0 { archiving = nil } }), titleVisibility: .visible) {
            if let session = archiving {
                Button(session.running ? "Archive and stop" : "Archive") {
                    Task { do { try await chat.sessionList.archive(session, archived: true, stopActivity: session.running) } catch { sessionError = (error as? DSHError)?.code ?? "E_TRANSPORT" } }
                    archiving = nil
                }
            }
        } message: { Text("Archived chats can be restored.") }
        .alert("Rename chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let session = renaming { Task { await chat.sessionList.rename(session, to: newTitle) } }
                renaming = nil
            }
        }
        .confirmationDialog("Delete this chat permanently?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let session = deleting { Task { deleteError = await chat.sessionList.delete(session) } }
                deleting = nil
            }
        } message: {
            Text("The chat and its history are removed from this device. This cannot be undone.")
        }
        .alert("Could not delete the chat", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK") { deleteError = nil }
        } message: { Text(deleteError ?? "") }
    }

    private var filtered: [SessionSummary] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return chat.sessionList.sessions.filter {
            chat.workspace.state.archived.contains($0.id) == showArchived && (q.isEmpty || ($0.title ?? "").lowercased().contains(q))
        }
    }

    private var pinnedSessions: [SessionSummary] {
        guard !showArchived else { return [] }
        return chat.workspace.state.pinned.compactMap { id in filtered.first { $0.id == id } }
    }
    private var groups: [(title: String, sessions: [SessionSummary])] {
        let filtered = self.filtered.filter { showArchived || !chat.workspace.state.pinned.contains($0.id) }
        if groupByWorkspace {
            let assigned = Set(chat.workspace.state.items.flatMap(\.sessionIds))
            return (chat.workspace.state.items.map { workspace in
                (title: workspace.title, sessions: filtered.filter { workspace.sessionIds.contains($0.id) })
            } + [(title: String(localized: "Other chats"), sessions: filtered.filter { !assigned.contains($0.id) })]).filter { !$0.sessions.isEmpty }
        }
        let calendar = Calendar.current
        var today: [SessionSummary] = [], week: [SessionSummary] = [], older: [SessionSummary] = []
        for session in filtered {
            if calendar.isDateInToday(session.updatedAt) { today.append(session) }
            else if let days = calendar.dateComponents([.day], from: session.updatedAt, to: Date()).day, days < 7 { week.append(session) }
            else { older.append(session) }
        }
        return [(String(localized: "Today"), today), (String(localized: "This week"), week), (String(localized: "Earlier"), older)]
            .filter { !$0.1.isEmpty }
    }

    private func row(_ session: SessionSummary) -> some View {
        let selected = session.id == chat.transcript.currentSessionId
        return Button { Task { await chat.transcript.open(session) }; close() } label: {
            HStack {
                Text(session.title ?? String(localized: "Untitled chat"))
                    .font(.system(size: 16, weight: selected ? .semibold : .regular))
                    .foregroundStyle(DS.ink).lineLimit(1)
                Spacer(minLength: 8)
                if session.running { Circle().fill(theme.accent).frame(width: 7, height: 7) }
            }
            .padding(.horizontal, 10).frame(height: 44)
            .background(selected ? DS.surfaceHigh : .clear, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if chat.workspace.state.archived.contains(session.id) {
                Button("Restore") { Task { do { try await chat.sessionList.archive(session, archived: false) } catch { sessionError = (error as? DSHError)?.code ?? "E_TRANSPORT" } } }
            } else {
                Button(chat.workspace.state.pinned.contains(session.id) ? "Unpin" : "Pin") {
                    Task { do { try await chat.sessionList.pin(session, pinned: !chat.workspace.state.pinned.contains(session.id)) } catch { sessionError = (error as? DSHError)?.code ?? "E_TRANSPORT" } }
                }
                Button("Archive") { archiving = session }
            }
            Button { newTitle = session.title ?? ""; renaming = session } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) { deleting = session } label: { Label("Delete", systemImage: "trash") }
        }
    }
}
