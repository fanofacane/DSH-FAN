// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import DSHClient
import Foundation

extension AppSession {
    func smokeT10(_ result: FeatureSmokeContext) async throws {
        let presets = try await self.connection.agentAPI.list()
        guard let preset = presets.first(where: { $0.isDefault && !$0.hasBrokenField }) ?? presets.first,
              let presetId = preset.id else { throw DSHError("E_PRESET_CATALOG") }
        let document = try await self.connection.agentAPI.read(agentPreset: presetId)
        guard document.content?.isEmpty == false else { throw DSHError("E_PRESET_READ") }
        try await self.agents.chooseAgentPreset(presetId)
        guard self.agents.selectedAgentPreset == presetId, self.transcript.canSend else { throw DSHError(self.connection.keyConfigured ? "E_PRESET_SELECT" : "E_NEEDS_USER_KEY") }
        await self.transcript.send("请启动一个可继续对话的子代理（mode=continuable），任务是只回复 child-ready。等待它完成后向我简短汇报。不要执行命令，不要写文件。")
        try await smokeWait(seconds: 180) { !self.transcript.busy && !self.control.projection.subagents(parent: self.transcript.currentSessionId ?? "").isEmpty }
        guard let parent = self.transcript.currentSessionId, let route = self.control.projection.subagents(parent: parent).first else { throw DSHError("E_CHILD_CATALOG") }
        var ready = false, followup = false
        func observe(_ record: LogEvent) {
            if case .assistantMessage(_, _, _, let message, _) = record {
                ready = ready || message.text.contains("child-ready")
                followup = followup || message.text.contains("child-followup")
            }
        }
        let observer = Task { @MainActor in
            do {
                for try await event in try await self.agents.childEvents(route) {
                    switch event {
                    case .snapshot(let records, _): for record in records { observe(record) }
                    case .event(let record): observe(record)
                    default: break
                    }
                }
            } catch {}
        }
        defer { observer.cancel() }
        try await smokeWait { ready }
        guard route.canPrompt else { throw DSHError("E_SMOKE_CHILD_NOT_CONTINUABLE") }
        try await self.agents.promptChild(route, text: "只回复 child-followup")
        try await smokeWait(seconds: 90) { followup }
        try await self.agents.interruptChild(route)
        result.set("presetReadSelect", true); result.set("childReadThroughParent", true)
        result.set("followup", true); result.set("interrupt", true); result.set("realModel", true)
    }
}
#endif
