// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import SwiftUI

struct SchedulesPage: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    @Environment(\.dismiss) private var dismiss
    @State private var tasks: [ScheduleEntry] = []
    @State private var selected: ScheduleEntry?
    @State private var error: String?
    @State private var currentOnly = false
    var body: some View {
        SettingsPage(title: "Scheduled tasks") {
            if chat.transcript.currentSessionId != nil { Toggle("Current chat only", isOn: $currentOnly).type(.bodySmall).tint(theme.accent).padding(.bottom, 12) }
            SettingsGroup {
                ForEach(tasks.filter { !currentOnly || $0.sessionId == chat.transcript.currentSessionId }) { task in
                    Button { selected = task } label: {
                        SettingsRow(title: "", subtitle: task.active ? String(localized: "Active") : String(localized: "Inactive"), verbatim: task.title) {
                            if let date = task.scheduledAt { Text(date, format: .dateTime.month().day().hour().minute()).type(.bodySmall).foregroundStyle(DS.inkFaint) }
                            else { SettingsChevron() }
                        }
                    }.buttonStyle(.plain)
                }
                if tasks.isEmpty { SettingsRow(title: "No scheduled tasks") { EmptyView() } }
            }
            MistButton(title: "Ask DSH to create a task") {
                chat.transcript.composerInsertion = String(localized: "Create a scheduled task: describe when it should run and what it should do.") + "\n"
                chat.transcript.requestComposerFocus()
                dismiss()
            }.disabled(chat.connection.state != .ready || chat.transcript.busy).padding(.bottom, 12)
            MistButton(title: "Refresh", kind: .secondary) { Task { await load() } }
            Text("Tasks run on the connected host. This phone’s engine must stay running.").type(.bodySmall).foregroundStyle(DS.inkFaint).padding(.top, 12)
            if let error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger) }
        }
        .task(id: chat.connection.state) { if chat.connection.state == .ready { await load() } }
        .sheet(item: $selected, onDismiss: { Task { await load() } }) { task in NavigationStack { ScheduleEditor(task: task) } }
    }
    private func load() async {
        do { tasks = try await chat.schedule.schedules(); error = nil }
        catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
    }
}

private struct ScheduleEditor: View {
    @Environment(AppSession.self) private var chat
    @Environment(\.dismiss) private var dismiss
    let task: ScheduleEntry
    @State private var title = ""
    @State private var prompt = ""
    @State private var changeTiming = false
    @State private var kind = "at"
    @State private var date = Date().addingTimeInterval(3600)
    @State private var zone = TimeZone.current.identifier
    @State private var seconds = "3600"
    @State private var expression = "0 9 * * *"
    @State private var weekdays: Set<Int> = [1]
    @State private var busy = false
    @State private var error: String?
    @State private var deleting = false
    @State private var initialized = false
    private var timeZone: TimeZone? { TimeZone(identifier: zone) }
    var body: some View {
        SettingsPage(title: "Scheduled task") {
            SettingsGroup {
                TextField("Title", text: $title).padding(16)
                RowDivider()
                TextField("Task instruction", text: $prompt, axis: .vertical).lineLimit(3...12).padding(16)
            }
            SettingsGroup {
                SettingsToggleRow(title: "Change run time", isOn: $changeTiming)
                if changeTiming {
                    Picker("Timing", selection: $kind) {
                        Text("Once").tag("at"); Text("Every interval").tag("every"); Text("Daily").tag("daily")
                        Text("Weekly").tag("weekly"); Text(verbatim: "Cron").tag("cron")
                    }.padding(12)
                    if kind == "every" {
                        TextField("Interval in seconds (at least 60)", text: $seconds).keyboardType(.numberPad).padding(16)
                    } else {
                        TextField("Time zone", text: $zone).textInputAutocapitalization(.never).autocorrectionDisabled().padding(16)
                        if kind == "cron" { TextField("Cron expression", text: $expression).textInputAutocapitalization(.never).autocorrectionDisabled().padding(16) }
                        else { DatePicker("Run at", selection: $date, displayedComponents: kind == "at" ? [.date, .hourAndMinute] : [.hourAndMinute]).environment(\.timeZone, timeZone ?? .current).padding(16) }
                    }
                    if kind == "weekly" {
                        ForEach(1...7, id: \.self) { day in
                            Toggle(Calendar.current.weekdaySymbols[day % 7], isOn: Binding(get: { weekdays.contains(day) }, set: { if $0 { weekdays.insert(day) } else { weekdays.remove(day) } })).padding(.horizontal, 16)
                        }.padding(.bottom, 12)
                    }
                }
            }
            if let error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger).padding(.bottom, 12) }
            MistButton(title: "Save changes", busy: busy) {
                busy = true
                Task {
                    do {
                        let timing = changeTiming ? try timingChange() : nil
                        _ = try await chat.schedule.updateSchedule(task, title: title, prompt: prompt, timing: timing)
                        dismiss()
                    } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
                    busy = false
                }
            }.disabled(busy || !task.active || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            NavigationLink { ScheduleHistoryPage(task: task) } label: { SettingsRow(title: "Delivery history") }.buttonStyle(.plain).padding(.vertical, 12)
            MistButton(title: "Delete task", kind: .danger) { deleting = true }.disabled(busy)
        }
        .onAppear {
            guard !initialized else { return }; initialized = true
            title = task.title; prompt = task.prompt
            kind = ["at", "every", "daily", "weekly", "cron"].contains(task.kind) ? task.kind : "at"
            zone = task.timeZone ?? TimeZone.current.identifier
            seconds = String(task.everySeconds ?? 3600)
            expression = task.expression ?? "0 9 * * *"
            weekdays = Set(task.weekdays ?? [1])
            if let value = task.scheduledAt { date = value }
            if let time = task.time {
                let parts = time.split(separator: ":").compactMap { Int($0) }
                if parts.count >= 2 {
                    var calendar = Calendar.current; calendar.timeZone = timeZone ?? .current
                    date = calendar.date(bySettingHour: parts[0], minute: parts[1], second: parts.count > 2 ? parts[2] : 0, of: Date()) ?? date
                }
            }
        }
        .confirmationDialog("Delete this task and its history?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete task", role: .destructive) {
                busy = true
                Task {
                    do { try await chat.schedule.deleteSchedule(task); dismiss() }
                    catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
                    busy = false
                }
            }
        }
    }
    private func timingChange() throws -> ScheduleChange {
        if kind == "every" {
            guard let interval = Int(seconds), interval >= 60 else { throw DSHError("frequency_too_high") }
            return .every(seconds: interval)
        }
        guard let timeZone else { throw DSHError("invalid_timezone") }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = timeZone; formatter.dateFormat = "HH:mm:ss"
        let time = formatter.string(from: date)
        if kind == "at" {
            formatter.dateFormat = "yyyy-MM-dd"
            return .at(date: formatter.string(from: date), time: time, timeZone: zone)
        }
        if kind == "cron" { return .cron(expression: expression, timeZone: zone) }
        if kind == "weekly" {
            guard !weekdays.isEmpty else { throw DSHError("invalid_rule") }
            return .weekly(time: time, timeZone: zone, weekdays: weekdays.sorted())
        }
        return .daily(time: time, timeZone: zone)
    }
}

private struct ScheduleHistoryPage: View {
    @Environment(AppSession.self) private var chat
    let task: ScheduleEntry
    @State private var records: [ScheduleDelivery] = []
    @State private var cursor: String?
    @State private var pruned = false
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        SettingsPage(title: "Delivery history") {
            SettingsGroup {
                ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                    VStack(alignment: .leading, spacing: 6) {
                        if let date = record.deliveredAt { Text(date, format: .dateTime).type(.bodyMedium) }
                        if let prompt = record.prompt { Text(verbatim: prompt).type(.bodySmall).foregroundStyle(DS.inkFaint) }
                    }.padding(16)
                }
                if records.isEmpty && !loading { SettingsRow(title: "No deliveries yet") { EmptyView() } }
            }
            if pruned { Text("Earlier delivery history was pruned by the host.").type(.bodySmall).foregroundStyle(DS.inkFaint) }
            if let error { Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger) }
            if cursor != nil { MistButton(title: "Load more", busy: loading) { Task { await load(more: true) } }.disabled(loading) }
        }.task { await load(more: false) }
    }
    private func load(more: Bool) async {
        loading = true; defer { loading = false }
        do {
            let response = try await chat.connection.scheduleAPI.history(sessionId: task.sessionId, id: task.taskId, limit: 20, before: more ? cursor : nil)
            let next = response.records ?? []
            if more { records += next } else { records = next }
            cursor = response.nextBefore; pruned = response.earlierRecordsPruned; error = nil
        } catch { self.error = (error as? DSHError)?.code ?? "E_TRANSPORT" }
    }
}
