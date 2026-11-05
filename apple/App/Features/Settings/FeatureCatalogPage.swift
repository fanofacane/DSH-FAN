// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/features/{skills_page,jobs_page}.dart.
import DSHClient
import SwiftUI

struct FeatureCatalogPage: View {
    enum Kind: String { case skills, jobs }
    let kind: Kind
    @Environment(AppSession.self) private var chat
    @State private var skills: [HostSkill] = []
    @State private var jobs: [HostJob] = []
    @State private var selected: HostSkill?
    @State private var loading = false
    @State private var error: String?
    @State private var retry = 0

    private var session: String? { chat.transcript.currentSessionId }

    var body: some View {
        SettingsPage(title: kind == .skills ? "Skills" : "Background jobs") {
            if loading { ProgressView().frame(maxWidth: .infinity).padding(Space.lg) }
            if let error {
                Text("Request failed: \(error)").settingsType(.bodySmall).foregroundStyle(DS.danger)
                MistButton(title: "Retry", kind: .secondary) { retry += 1 }
            } else if !loading && skills.isEmpty && jobs.isEmpty {
                SettingsGroup {
                    SettingsRow(title: session == nil ? "Open a chat to view its features." :
                                    kind == .skills ? "No skills reported" : "No jobs reported") { EmptyView() }
                }
            }
            if kind == .skills, !skills.isEmpty {
                SettingsGroup {
                    ForEach(skills) { skill in
                        Button { selected = skill } label: {
                            SettingsRow(glyph: .sparkle, title: "", subtitle: skill.description, verbatim: "/" + skill.name) {
                                SettingsChevron()
                            }
                        }.buttonStyle(SettingsPressStyle())
                    }
                }
            } else if kind == .jobs {
                jobGroup("In progress", jobs.filter(\.isRunning))
                jobGroup("Finished", jobs.filter { !$0.isRunning })
            }
        }
        .task(id: "\(chat.connection.generation)-\(session ?? "")-\(retry)") { await load() }
        .sheet(item: $selected) { skill in
            SettingsSheet(title: LocalizedStringKey("/" + skill.name), locked: true) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.md) {
                        if let description = skill.description { Text(verbatim: description).settingsType(.body) }
                        if let note = skill.whenToUse { Text(verbatim: note).settingsType(.bodyMedium) }
                        if !skill.modelInvocable {
                            Text("Only available as a slash command.").settingsType(.bodySmall).foregroundStyle(DS.inkFaint)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.scrollBounceBehavior(.basedOnSize)
            }.presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder private func jobGroup(_ title: LocalizedStringKey, _ entries: [HostJob]) -> some View {
        if !entries.isEmpty {
            SettingsGroup(header: title) {
                ForEach(entries) { job in
                    SettingsRow(glyph: AppIcon.terminal, title: "Background job", subtitle: job.kind.isEmpty ? nil : job.kind) {
                        switch job.status {
                        case "running": StatusChip(tone: .busy, label: "Running")
                        case "stopping": StatusChip(tone: .busy, label: "Stopping")
                        case "completed": StatusChip(tone: .ok, label: "Completed")
                        case "failed": StatusChip(tone: .error, label: "Failed")
                        case "killed": StatusChip(tone: .idle, label: "Stopped")
                        default: StatusChip(tone: .idle, label: "Unknown")
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        skills = []; jobs = []; error = nil; loading = false
        #if DEBUG
        if DebugPageRegistry.usesFixture {
            if kind == .skills { skills = [.init(name: "review", description: "Review a change")] }
            else { jobs = [.init(id: "test", kind: "command", status: "running"), .init(id: "example", kind: "command", status: "completed")] }
            return
        }
        #endif
        guard let session, chat.connection.state == .ready else { return }
        let generation = chat.connection.generation
        let stillCurrent = { !Task.isCancelled && generation == chat.connection.generation && session == self.session }
        loading = true
        defer { if stillCurrent() { loading = false } }
        do {
            let api = FeatureCatalogAPI(client: try chat.connection.requireClient())
            if kind == .skills {
                let response = try await api.skills(sessionId: session)
                if stillCurrent() { skills = response }
            } else {
                for try await response in try await api.jobs(sessionId: session) {
                    guard stillCurrent() else { return }
                    jobs = response
                    loading = false
                }
            }
        } catch { if stillCurrent() { self.error = appErrorCode(error) } }
    }
}
