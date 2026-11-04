// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import SwiftUI

struct WorkspacesPage: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    @Environment(\.dismiss) private var dismiss
    var selecting = false
    @State private var browse = false
    @State private var register = false
    @State private var rename: WorkspaceRecord?
    @State private var name = ""
    @State private var deleting: WorkspaceRecord?
    @State private var error: String?
    var body: some View {
        SettingsPage(title: selecting ? "New chat location" : "Workspaces") {
            if selecting {
                MistButton(title: "Use host default directory", kind: .secondary) {
                    chat.workspace.chooseWorkspace(nil); dismiss()
                }.disabled(chat.transcript.busy).padding(.bottom, 16)
            }
            SettingsGroup {
                ForEach(chat.workspace.state.items) { workspace in
                    Button {
                        chat.workspace.chooseWorkspace(workspace.id)
                        if selecting { dismiss() }
                    } label: {
                        SettingsRow(title: "", subtitle: workspace.path, verbatim: workspace.title) {
                            if chat.workspace.selectedWorkspaceId == workspace.id { Image(systemName: "checkmark").foregroundStyle(theme.accent) }
                        }
                    }.buttonStyle(.plain).disabled(chat.transcript.busy)
                    .contextMenu {
                        Button("Rename") { rename = workspace; name = workspace.title }
                        Button("Remove workspace", role: .destructive) { deleting = workspace }
                    }
                    RowDivider()
                }
                if chat.workspace.state.items.isEmpty { SettingsRow(title: "No workspaces yet") { EmptyView() } }
            }
            MistButton(title: selecting ? "Browse working directory" : "Register workspace") { register = !selecting; browse = true }
                .disabled(chat.connection.state != .ready || chat.transcript.busy)
            if let code = error ?? chat.workspace.error { Text("Request failed: \(code)").type(.bodySmall).foregroundStyle(DS.danger).padding(.top, 12) }
        }
        .sheet(isPresented: $browse) {
            NavigationStack {
                DirectoryBrowser { path in
                    if register {
                        _ = try await chat.workspace.registerWorkspace(path); browse = false
                    } else { chat.workspace.chooseDirectory(path); browse = false; dismiss() }
                }
            }
        }
        .alert("Rename workspace", isPresented: Binding(get: { rename != nil }, set: { if !$0 { rename = nil } })) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) { rename = nil }
            Button("Save") {
                if let workspace = rename {
                    Task { do { try await chat.workspace.renameWorkspace(workspace.id, title: name) } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" } }
                }
                rename = nil
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog("Remove workspace registration?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Remove workspace", role: .destructive) {
                if let workspace = deleting {
                    Task { do { try await chat.workspace.removeWorkspace(workspace.id) } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" } }
                }
                deleting = nil
            }
        } message: { Text("The folder and its chats are kept. Chats become ungrouped.") }
    }
}

struct DirectoryBrowser: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    @Environment(\.dismiss) private var dismiss
    let choose: (String) async throws -> Void
    @State private var choosing = false
    @State private var requested: String?
    @State private var listing = DirectoryListing()
    @State private var error: String?
    @State private var loading = false
    private var path: String { listing.path ?? "" }
    var body: some View {
        SettingsPage(title: "Choose a folder", showsBack: false) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Array(listing.crumbs.enumerated()), id: \.offset) { _, crumb in
                        Button { requested = crumb.path } label: { Text(verbatim: crumb.name) }.buttonStyle(.plain)
                        Image(systemName: "chevron.right").font(.caption)
                    }
                }.foregroundStyle(theme.accent).padding(.bottom, 16)
            }
            Text(verbatim: path).font(Mono.font(13, scale: theme.readingScale)).foregroundStyle(DS.inkFaint).padding(.bottom, 12)
            if loading { ProgressView() }
            SettingsGroup {
                ForEach(Array(listing.entries.enumerated()), id: \.offset) { _, entry in
                    Button { requested = entry.path } label: {
                        SettingsRow(title: "", verbatim: entry.name) {
                            Image(systemName: "folder").foregroundStyle(theme.accent)
                        }
                    }.buttonStyle(.plain)
                }
            }
            if listing.truncated { Text("This folder has more entries than the host can list.").type(.bodySmall) }
            if let error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger) }
            MistButton(title: "Use this folder", busy: choosing) {
                choosing = true
                Task {
                    do { try await choose(path) }
                    catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
                    choosing = false
                }
            }.disabled(path.isEmpty || loading || error != nil || choosing)
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .task(id: requested) {
            loading = true; error = nil
            do {
                let response = try await chat.connection.workspaceAPI.listDirectory(path: requested)
                try Task.checkCancellation(); listing = response
            } catch { if !Task.isCancelled { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" } }
            if !Task.isCancelled { loading = false }
        }
    }
}
