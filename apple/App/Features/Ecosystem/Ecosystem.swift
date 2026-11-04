// SPDX-License-Identifier: AGPL-3.0-or-later
// App side of the ecosystem pieces: Live Activity for a running turn, deep
// links from widgets / controls, and the share-extension inbox.
import ActivityKit
import DSHClient
import Foundation
import SwiftUI
import UIKit

/// Starts, updates and ends the turn Live Activity from the chat state.
@MainActor
final class TurnActivityController {
    private var activity: Activity<DSHActivityAttributes>?
    private var last: DSHActivityAttributes.ContentState?
    private var ticker: Task<Void, Never>?
    private var wasBusy = false

    func run(with chat: AppSession) {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick(chat)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func state(_ chat: AppSession) -> DSHActivityAttributes.ContentState {
        let running = chat.transcript.items.flatMap(\.tools).filter { $0.result == nil }
        if chat.requests.currentApproval != nil || chat.requests.currentQuestion != nil {
            return .init(phase: .waiting, detail: "", tools: running.count)
        }
        if let tool = running.last {
            return .init(phase: .working, detail: Self.summary(tool), tools: running.count)
        }
        if let draft = chat.transcript.items.last(where: { $0.state == .streaming }), !draft.text.isEmpty {
            return .init(phase: .replying, detail: "", tools: 0)
        }
        return .init(phase: .thinking, detail: "", tools: 0)
    }

    private func tick(_ chat: AppSession) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if chat.transcript.busy {
            let next = state(chat)
            if activity == nil {
                let title = chat.transcript.currentTitle ?? String(localized: "New chat")
                activity = try? Activity.request(attributes: DSHActivityAttributes(title: title),
                                                 content: .init(state: next, staleDate: nil))
                last = next
            } else if next != last {
                last = next
                await activity?.update(.init(state: next, staleDate: nil))
            }
        } else if wasBusy, let current = activity {
            let failed = chat.transcript.items.last?.role == .notice
            let final = DSHActivityAttributes.ContentState(phase: failed ? .failed : .done, detail: "", tools: 0)
            await current.end(.init(state: final, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(4)))
            activity = nil; last = nil
        }
        wasBusy = chat.transcript.busy
    }

    /// The command or path only; never message text.
    private static func summary(_ tool: ToolRow) -> String {
        let args = (try? JSONValue(data: Data(tool.arguments.utf8)))?.object ?? [:]
        let value = args["command"]?.string ?? args["file_path"]?.string ?? args["path"]?.string ?? args["pattern"]?.string
        return String((value ?? tool.name).prefix(80))
    }
}

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
