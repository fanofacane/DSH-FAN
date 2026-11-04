// SPDX-License-Identifier: AGPL-3.0-or-later
// Compiled into both the app and the DSHWidgets extension.
import ActivityKit
import Foundation

/// Live Activity for a running turn (lock screen + Dynamic Island).
struct DSHActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable { case thinking, working, waiting, replying, done, failed }
        var phase: Phase
        /// Short detail, e.g. the running tool ("ls -la /root"). Never message text.
        var detail: String
        var tools: Int
    }
    /// The chat title when the turn started.
    var title: String
}

/// Deep links shared by widgets, controls and the app.
enum DSHLink {
    static let scheme = "dshapp"
    /// Opens a new chat with the composer focused.
    static let ask = URL(string: "dshapp://ask")!
    static let appGroup = "group.io.github.fanofacane.dsh"
}

/// App Group inbox written by the share extension, read by the app.
struct SharedInboxItem: Codable {
    var text: String
    /// File names of images in the inbox directory.
    var images: [String]
    var created: Date
}

enum SharedInbox {
    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: DSHLink.appGroup)?
            .appendingPathComponent("ShareInbox", isDirectory: true)
    }
}
