// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
public struct SubagentRoute: Identifiable, Equatable {
    public let parent: String
    public let id: String
    public let mode: String
    public let label: String
    public init?(_ row: [String: Any], parent: String) {
        guard let id = row["id"] as? String, !id.isEmpty, !parent.isEmpty else { return nil }
        self.id = id; self.parent = parent
        mode = row["mode"] as? String ?? "unknown"; label = row["label"] as? String ?? id
    }
    public var canPrompt: Bool { mode == "continuable" }
    public var canOpen: Bool { mode != "external" }
    public var address: [String: Any] {
        ["kind": "subagent", "parentSessionId": parent, "childSessionId": id,
         "mode": ["one-shot", "continuable"].contains(mode) ? mode : "unknown"]
    }
}
