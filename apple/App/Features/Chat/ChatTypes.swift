// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import Foundation

struct ToolRow: Identifiable, Equatable {
    let id: String
    var name: String
    var arguments: String
    var result: String?
    var failed = false
    var presentation = ToolPresentation(nil)

    var args: [String: JSONValue] { (try? JSONValue(data: Data(arguments.utf8)).object) ?? [:] }
    var family: ToolFamily { ToolFamily(name: name, operation: args["command"]?.string) }
}

struct ChatItem: Identifiable, Equatable {
    enum Role { case user, assistant, notice }
    enum State: Equatable { case done, streaming, pending, failed(String) }
    let id: String
    let role: Role
    var text = ""
    var reasoning = ""
    var tools: [ToolRow] = []
    var imageCount = 0
    var images: [MessageImageReference] = []
    var state = State.done
    var requestId: String?
    /// Log seq of a committed message (nil for drafts, pending and notices).
    var seq: Int?
}

enum ConnectionState: Equatable { case idle, connecting, ready, failed(String) }
