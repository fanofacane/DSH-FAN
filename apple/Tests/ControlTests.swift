// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing
@testable import DSHClient
struct ControlTests {
    @Test func contracts() {
        var state = SessionControlState()
        state.apply(["type": "baseline", "value": ["projections": ["s": ["asOfSeq": 10, "values": ["title": "start"]]]]])
        state.apply(["sessionId": "s", "key": "todos", "value": [["content": "one", "status": "pending"]], "seq": 12])
        state.apply(["sessionId": "s", "key": "title", "value": "next", "seq": 12])
        state.apply(["sessionId": "s", "key": "title", "value": "stale", "seq": 11])
        #expect(state.values["s"]?.title == "next")
        #expect(state.values["s"]?.todos.count == 1)
        state.apply(["sessionId": "s", "key": "goal", "value": NSNull(), "seq": 13])
        #expect(state.values["s"]?.goal == nil)
        state.apply(["type": "baseline", "value": ["projections": [String: Any]()]])
        #expect(state.values.isEmpty)
    }
}
