// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import SwiftUI

struct RunInsightsPage: View {
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    @Environment(HostStore.self) private var hosts
    @Environment(EngineModel.self) private var engine
    private var metrics: SessionMetrics { chat.control.projection.metrics }
    private var latest: [RunFact] {
        let facts = chat.transcript.runFacts
        if let start = facts.lastIndex(where: { $0.kind == "turn/start" }) { return Array(facts[start...]) }
        return facts
    }
    var body: some View {
        SettingsPage(title: "Usage and run info") {
            SettingsGroup(header: "Context") {
                if let fraction = metrics.fraction {
                    ProgressView(value: fraction).tint(fraction >= 0.85 ? DS.danger : fraction >= 0.6 ? DS.warn : theme.accent).padding(16)
                }
                metric("Last request tokens", metrics.pressureTokens)
                metric("Context window", metrics.contextWindow)
                metric("Next request estimate", metrics.projectedTokens)
            }
            SettingsGroup(header: "Session tokens", footer: "Input includes uncached input, cache reads and cache writes. No cost estimate is calculated.") {
                metric("Total input", metrics.input)
                metric("Uncached input", metrics.uncached)
                metric("Cache reads", metrics.cacheRead)
                metric("Cache writes", metrics.cacheWrite)
                metric("Output", metrics.output)
            }
            SettingsGroup(header: "Run info") {
                SettingsRow(title: "Host", subtitle: hosts.activeHost?.name ?? String(localized: "This phone")) { EmptyView() }
                SettingsRow(title: "Selected model", subtitle: chat.connection.selectedModel?.id) { EmptyView() }
                metric("Turns", metrics.turns)
                SettingsRow(title: "Model time", subtitle: duration(metrics.modelMs)) { EmptyView() }
                SettingsRow(title: "Tool time", subtitle: duration(metrics.toolMs)) { EmptyView() }
                if !hosts.isRemote { SettingsRow(title: "Local engine", subtitle: String(localized: engine.status.phase.titleResource)) { EmptyView() } }
            }
            SettingsGroup(header: "Latest trajectory", footer: "Times come from durable host events. Unfinished work has no invented end time.") {
                if chat.transcript.historyHasMore { Text("Showing recent history only.").type(.bodySmall).foregroundStyle(DS.inkFaint).padding(12) }
                if latest.isEmpty { SettingsRow(title: "No run events yet") { EmptyView() } }
                ForEach(latest) { fact in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(theme.accent).frame(width: 6, height: 6)
                        VStack(alignment: .leading) {
                            Text(label(fact.kind)).type(.bodyMedium).foregroundStyle(DS.ink)
                            if let tool = fact.toolName { Text(verbatim: tool).font(Mono.font(12, scale: theme.readingScale)).foregroundStyle(DS.inkFaint) }
                        }
                        Spacer()
                        Text(fact.time, style: .time).font(Mono.font(12, scale: theme.readingScale)).foregroundStyle(DS.inkFaint)
                    }.padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
        }
    }
    private func metric(_ label: LocalizedStringKey, _ value: Int?) -> some View {
        SettingsRow(title: label) {
            Text(verbatim: value.map { $0.formatted() } ?? String(localized: "Not reported")).font(Mono.font(13, scale: theme.readingScale)).foregroundStyle(DS.inkMuted)
        }
    }
    private func duration(_ millis: Int?) -> String {
        guard let millis else { return String(localized: "Not reported") }
        return String(format: "%.2f s", Double(millis) / 1000)
    }
    private func label(_ kind: String) -> LocalizedStringKey {
        switch kind {
        case "turn/start": "Turn started"
        case "turn/end": "Turn ended"
        case "step/start": "Step started"
        case "step/end": "Step ended"
        case "assistant/attempt": "Model attempt recorded"
        case "assistant/message": "Model reply stored"
        case "tool/call": "Tool started"
        case "tool/result": "Tool result stored"
        case "llm/retry": "Model retry"
        case "compaction/start": "Compaction started"
        case "compaction/end": "Compaction ended"
        default: "Prompt stored"
        }
    }
}
