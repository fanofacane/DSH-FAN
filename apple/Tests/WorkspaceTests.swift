// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing
@testable import DSHClient
struct WorkspaceTests {
    @Test func contracts() {
        var state = WorkspaceState()
        state.apply(["type": "baseline", "value": ["items": [["workspaceId": "a", "path": "/a", "title": "A", "sessionIds": ["s"]]], "archivedSessionIds": ["x"], "pinnedSessionIds": ["s"]]])
        state.apply(["type": "upsert", "workspace": ["workspaceId": "b", "path": "/b", "title": "B"]])
        state.apply(["type": "order", "workspaceIds": ["a", "b"]])
        #expect(state.items.map(\.id) == ["a", "b"])
        #expect(state.items[0].sessionIds == ["s"] && state.archived.contains("x") && state.pinned == ["s"])
        state.apply(["type": "remove", "workspaceId": "a"])
        #expect(state.items.map(\.id) == ["b"])
        state.apply(["type": "replace", "value": ["items": []]])
        #expect(state.items.isEmpty && state.archived.isEmpty && state.pinned.isEmpty)
    }
}
