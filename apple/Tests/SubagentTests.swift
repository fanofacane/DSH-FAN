// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing
@testable import DSHClient
struct SubagentTests {
    @Test func contracts() {
        let child = SubagentRoute(["id": "child", "mode": "continuable", "label": "Task"], parent: "parent")!
        #expect(child.canPrompt && child.canOpen)
        #expect(child.address["kind"] as? String == "subagent")
        #expect(child.address["parentSessionId"] as? String == "parent")
        #expect(child.address["childSessionId"] as? String == "child")
        #expect(child.address["sessionId"] == nil)
        #expect(!SubagentRoute(["id": "c", "mode": "one-shot"], parent: "p")!.canPrompt)
        #expect(!SubagentRoute(["id": "c", "mode": "external"], parent: "p")!.canOpen)
        #expect(SubagentRoute(["id": ""], parent: "p") == nil)
    }
}
