// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import QuickLook
import SwiftUI
import WebKit

struct WorkspaceFilesHome: View {
    @Environment(AppSession.self) private var chat
    @State private var error: String?
    var body: some View {
        if let id = chat.transcript.currentSessionId { WorkspaceFilesPage(sessionId: id) }
        else {
            SettingsPage(title: "Files") {
                MistButton(title: "Open workspace files") {
                    Task { do { _ = try await chat.transcript.ensureSession() } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" } }
                }.disabled(chat.connection.state != .ready)
                if let error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger) }
            }
        }
    }
}

struct WorkspaceFilesPage: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    let sessionId: String
    var path = "."
    @State private var listing = WorkspaceFileListing()
    @State private var error: String?
    @State private var watchError: String?
    @State private var loading = false
    var body: some View {
        SettingsPage(title: "Files") {
            Text(verbatim: path).font(Mono.font(13, scale: theme.readingScale)).foregroundStyle(DS.inkFaint).padding(.bottom, 12)
            NavigationLink { ChangesPage() } label: { SettingsRow(title: "Latest turn changes") }.buttonStyle(.plain).padding(.bottom, 16)
            if loading { ProgressView() }
            SettingsGroup {
                ForEach(Array(listing.entries.enumerated()), id: \.offset) { _, entry in
                    let name = entry.name
                    let next = path == "." ? name : path + "/" + name
                    NavigationLink {
                        if entry.type == "directory" { WorkspaceFilesPage(sessionId: sessionId, path: next) }
                        else { FilePreviewPage(sessionId: sessionId, path: next) }
                    } label: {
                        SettingsRow(title: "", subtitle: entry.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }, verbatim: name) {
                            Image(systemName: entry.type == "directory" ? "folder" : "doc").foregroundStyle(theme.accent)
                        }
                    }.buttonStyle(.plain)
                }
            }
            if listing.truncated { Text("This folder has more entries than the host can list.").type(.bodySmall) }
            if let code = error ?? watchError { Text("Request failed: \(code)").type(.bodySmall).foregroundStyle(DS.danger) }
            MistButton(title: "Refresh", kind: .secondary) { Task { await load() } }
        }
        .task(id: path) {
            await load()
            do {
                for try await frame in try await chat.connection.filesAPI.changes(workspaceFileScopeId: sessionId, path: path) {
                    guard !Task.isCancelled else { return }
                    if ["ready", "change"].contains(frame.kind ?? "") { await load() }
                }
            } catch { if !Task.isCancelled { watchError = (error as? DSHError)?.code ?? "E_TRANSPORT" } }
        }
    }
    private func load() async {
        loading = true; defer { loading = false }
        do {
            let result = try await chat.connection.filesAPI.list(workspaceFileScopeId: sessionId, path: path)
            try Task.checkCancellation(); listing = result; error = nil
        } catch { if !Task.isCancelled { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" } }
    }
}

struct FilePreviewPage: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    @Environment(\.dismiss) private var dismiss
    let sessionId: String
    let path: String
    @State private var url: URL?
    @State private var directory: URL?
    @State private var html: String?
    @State private var text: String?
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        ZStack {
            AppBackdrop()
            VStack(spacing: 12) {
                HStack {
                    GlassIconButton(glyph: AppIcon.back, label: "Back") { dismiss() }
                    Text(verbatim: (path as NSString).lastPathComponent).type(.titleMedium).foregroundStyle(DS.ink).lineLimit(1)
                    Spacer()
                    if let url { ShareLink(item: url) { Image(systemName: "square.and.arrow.up").frame(width: 40, height: 40) }.accessibilityLabel(Text("Share")) }
                }.padding(.horizontal, 12)
                if loading { ProgressView().frame(maxHeight: .infinity) }
                else if let html { DocumentWebPreview(html: html) }
                else if let text {
                    ScrollView([.vertical, .horizontal]) { Text(verbatim: text).font(Mono.font(14, scale: theme.readingScale)).foregroundStyle(DS.ink).textSelection(.enabled).padding(16) }
                } else if let url { NativeDocumentPreview(url: url) }
                if let error {
                    Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger).padding()
                    MistButton(title: "Retry", kind: .secondary) { Task { await load() } }.padding(.horizontal, 16)
                }
                Spacer(minLength: 0)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: path) { await load() }
        .onDisappear { if let directory { try? FileManager.default.removeItem(at: directory) } }
    }
    private func load() async {
        loading = true; error = nil; url = nil; html = nil; text = nil
        defer { loading = false }
        do {
            if let directory { try? FileManager.default.removeItem(at: directory) }
            let cache = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-preview-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            directory = cache
            let bytes = try await chat.workspace.fileBytes(sessionId: sessionId, path: path)
            try Task.checkCancellation()
            let name = (path as NSString).lastPathComponent
            var destination = cache.appendingPathComponent(name.isEmpty ? "preview" : name)
            try bytes.write(to: destination, options: [.atomic, .completeFileProtection])
            let ext = destination.pathExtension.lowercased()
            if ["html", "htm"].contains(ext) {
                guard let value = String(data: bytes, encoding: .utf8) else { throw DSHError("E_PREVIEW_ENCODING") }
                html = value
            } else if !QLPreviewController.canPreview(destination as NSURL) {
                if ["doc", "docx", "xls", "xlsx", "ppt", "pptx"].contains(ext) {
                    let pdf = try await chat.workspace.officePDF(sessionId: sessionId, path: path)
                    try Task.checkCancellation()
                    guard pdf.count <= 50 * 1024 * 1024 else { throw DSHError("E_PREVIEW_TOO_LARGE") }
                    destination = cache.appendingPathComponent("Preview.pdf")
                    try pdf.write(to: destination, options: [.atomic, .completeFileProtection])
                } else if let value = String(data: bytes, encoding: .utf8) { text = value }
                else { throw DSHError("E_PREVIEW_UNSUPPORTED") }
            }
            url = destination
        } catch { if !Task.isCancelled { self.error = (error as? DSHError)?.code ?? "E_PREVIEW_FAILED" } }
    }
}

private struct NativeDocumentPreview: UIViewControllerRepresentable {
    let url: URL
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(_ url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
    func makeCoordinator() -> Coordinator { Coordinator(url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController(); controller.dataSource = context.coordinator; return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        if context.coordinator.url != url { context.coordinator.url = url; controller.reloadData() }
    }
}
private struct DocumentWebPreview: UIViewRepresentable {
    let html: String
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.loadHTMLString(html, baseURL: nil)
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
