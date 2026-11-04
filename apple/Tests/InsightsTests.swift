// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing
@testable import DSHClient
struct InsightsTests {
    @Test func contracts() {
        let usage = SessionMetrics(["tokenUsage": ["uncachedInputTokens": 10, "cacheReadTokens": 20, "cacheWriteTokens": 5, "outputTokens": 7], "contextPressure": ["pressureTokens": 25, "contextWindow": 100]])
        #expect(usage.input == 35 && usage.output == 7 && usage.fraction == 0.25)
        #expect(SessionMetrics([:]).input == nil)
        #expect(SessionMetrics(["tokenUsage": ["uncachedInputTokens": Int.max, "cacheReadTokens": 1]]).input == nil)
        let fact = RunFact(["seq": 1, "time": 1200.0, "type": "turn/start", "data": ["turn": 2]])!
        #expect(fact.turn == 2 && abs(fact.time.timeIntervalSince1970 - 1.2) < 0.000001)
        #expect(RunFact(["seq": 1, "type": "turn/start"]) == nil)
    }
}
