// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import DSHClient
import Foundation

extension AppSession {
    func smokeT12(_ result: FeatureSmokeContext) async throws {
        self.transcript.newChat(); await self.transcript.send("只回复 usage-ready")
        try await smokeWait(seconds: 90) { !self.transcript.busy && self.transcript.items.contains { $0.role == .assistant && $0.state == .done } }
        try await smokeWait { self.control.projection.metrics.output != nil }
        let usage = self.control.projection.metrics
        guard (usage.input ?? 0) > 0, (usage.output ?? 0) > 0,
              self.transcript.runFacts.contains(where: { $0.kind == "turn/start" }), self.transcript.runFacts.contains(where: { $0.kind == "turn/end" }) else { throw DSHError("E_INSIGHTS") }
        result.set("tokenUsage", true); result.set("durableTimeline", true); result.set("realModel", true)
        result.set("contextReported", usage.contextWindow != nil)
        result.set("statsReported", usage.turns != nil)
    }
}
#endif
