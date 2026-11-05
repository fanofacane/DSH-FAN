// SPDX-License-Identifier: AGPL-3.0-or-later
// App side of the ecosystem pieces: Live Activity for a running turn, deep
// links from widgets / controls, and the share-extension inbox.
import DSHClient
import Foundation
import SwiftUI
import UIKit

/// Text and images handed over by the share extension.
struct SharedDraft: Equatable {
    var text: String
    var images: [Data]
}

enum SharedInboxReader {
    /// Moves every pending share out of the App Group inbox.
    static func drain() -> [SharedDraft] {
        guard let directory = SharedInbox.directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        var drafts: [SharedDraft] = []
        for file in files where file.pathExtension == "json" {
            defer { try? FileManager.default.removeItem(at: file) }
            guard let data = try? Data(contentsOf: file),
                  let item = try? JSONDecoder().decode(SharedInboxItem.self, from: data) else { continue }
            let images = item.images.compactMap { name -> Data? in
                let url = directory.appendingPathComponent(name)
                defer { try? FileManager.default.removeItem(at: url) }
                return try? Data(contentsOf: url)
            }
            drafts.append(SharedDraft(text: item.text, images: images))
        }
        return drafts
    }
}
