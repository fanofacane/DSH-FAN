// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/settings/diagnostics_page.dart and ui/engine/diagnostics_export_card.dart.
import DSHClient
import DSHRuntime
import SwiftUI

enum DiagnosticExport {
    static func writeReviewed(_ text: String, reviewed: Bool) throws -> URL {
        guard reviewed else { throw DSHError("E_DIAGNOSTICS_REVIEW") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DSH-diagnostics-" + UUID().uuidString + ".txt")
        try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}

struct DiagnosticsSettingsPage: View {
    @Environment(EngineModel.self) private var engine
    @Environment(HostStore.self) private var hosts
    @Environment(AppSession.self) private var chat
    @State private var export = false
    @State private var log = false

    private var sample: Bool {
        #if DEBUG
        DebugPageRegistry.usesFixture
        #else
        false
        #endif
    }

    var body: some View {
        SettingsPage(title: "Diagnostics", subtitle: "Check engine status, connection and recent logs.") {
            SettingsGroup(header: "Runtime") {
                InfoRow(label: "Status", value: sample ? String(localized: "Running") :
                            SettingsEngineStatus(phase: engine.status.phase, safe: engine.safeModeOn).label)
                InfoRow(label: "Architecture", value: "arm64", mono: true)
                InfoRow(label: "Bundled version", value: sample ? "0.2.0-rc.2" : engine.status.bundledVersion ?? "—", mono: true)
                InfoRow(label: "Installed version", value: sample ? "0.2.0-rc.2" : engine.status.installedVersion ?? "—", mono: true)
                InfoRow(label: "Execution mode", value: "iSH", mono: true)
                InfoRow(label: "DSH", value: sample ? "0.2.0-rc.2" : engine.status.dshVersion ?? "—", mono: true)
                InfoRow(label: "Node.js", value: sample ? "24.22.1" : engine.status.nodeVersion ?? "—", mono: true)
                if let error = engine.status.errorCode { InfoRow(label: "Error", value: error, mono: true) }
            }
            SettingsGroup(header: "Connection") {
                InfoRow(label: "Address", value: engine.status.baseURL?.absoluteString ?? (sample ? "http://127.0.0.1:3080" : "—"), mono: true)
                InfoRow(label: "Client", value: sample || chat.connection.state == .ready ? String(localized: "Connected") : String(localized: "Disconnected"))
                InfoRow(label: "API key", value: chat.connection.keyConfigured ? String(localized: "Configured") : String(localized: "Not set"))
            }
            SettingsGroup(header: "Export", footer: "Only local engine logs are included; remote host logs are not collected.") {
                Button { export = true } label: {
                    SettingsRow(glyph: AppIcon.share, title: "Export diagnostics",
                                subtitle: String(localized: "Review the report before sharing."))
                }.buttonStyle(SettingsPressStyle()).settingAnchor("diagnostics-export")
                SettingsLink(glyph: AppIcon.terminal, title: "Engine logs") { DiagnosticLogPage(snapshot: snapshot) }
            }
        }
        .sheet(isPresented: $export) { DiagnosticReviewSheet(snapshot: snapshot) }
    }

    private var snapshot: String {
        let report = [
            "DSH Fan " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""),
            "Runtime: " + engine.status.phase.rawValue,
            "Engine: " + (engine.status.dshVersion ?? "—"),
            "Connection: " + (hosts.isRemote ? "remote" : "local"),
            "Logs:",
        ].joined(separator: "\n")
        if sample { return report + "\n[system] Engine is running.\n[stdout] Listening on 127.0.0.1:3080" }
        return report + "\n" + engine.logs.map { "[\($0.stream)] " + RuntimeLogs.redact($0.line) }.joined(separator: "\n")
    }
}

struct DiagnosticReviewSheet: View {
    let snapshot: String
    @State private var draft = ""
    @State private var reviewed = false
    @State private var export: URL?
    @State private var error: String?
    @State private var writing = false

    var body: some View {
        SettingsSheet(title: "Export diagnostics", locked: true) {
            Text("Automatic redaction can miss private information. Remove it before sharing.")
                .settingsType(.bodyMedium).foregroundStyle(DS.inkMuted)
            TextEditor(text: $draft).font(Mono.font(11))
                .scrollContentBackground(.hidden).padding(Space.sm).glass(.card)
                .frame(minHeight: 140)
                .accessibilityLabel("Review diagnostics")
            SheetGroup {
                SettingsToggleRow(title: "I reviewed this text for secrets", isOn: $reviewed)
            }
            if let error { Text("Request failed: \(error)").settingsType(.bodySmall).foregroundStyle(DS.danger) }
            if let export {
                ShareLink(item: export) { Label("Share reviewed log", systemImage: "square.and.arrow.up") }
                    .settingsType(.label)
            } else {
                MistButton(title: "Prepare reviewed log", busy: writing) {
                    do { export = try DiagnosticExport.writeReviewed(draft, reviewed: reviewed); error = nil }
                    catch { self.error = (error as? DSHError)?.code ?? "E_DIAGNOSTICS_EXPORT" }
                }.disabled(!reviewed || draft.isEmpty || writing)
            }
        }
        .presentationDetents([.large])
        .onAppear {
            draft = snapshot
            #if DEBUG
            writing = DebugPageRegistry.argument("-dsh-screen-fixture") == "busy"
            #endif
        }
        .onChange(of: draft) { _, _ in reviewed = false; clearExport() }
        .onChange(of: reviewed) { _, value in if !value { clearExport() } }
        .onDisappear { clearExport() }
    }

    private func clearExport() {
        if let export { try? FileManager.default.removeItem(at: export) }
        export = nil
    }
}

struct DiagnosticLogPage: View {
    let snapshot: String
    var body: some View {
        SettingsPage(title: "Engine logs") {
            Text(verbatim: snapshot)
                .font(Mono.font(11)).foregroundStyle(DS.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.md).background(DS.codeWell, in: RoundedRectangle(cornerRadius: Radius.md))
                .textSelection(.enabled)
        }
    }
}
