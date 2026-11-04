// SPDX-License-Identifier: AGPL-3.0-or-later
// Siri / Shortcuts entry points. The prompt is handed to the chat once the
// local engine is connected (the engine only runs while the app is open).
import AppIntents
import Foundation

struct AskDSHIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask DSH"
    static let description = IntentDescription("Opens DSH and asks the local agent in a new chat.")
    static let openAppWhenRun = true

    @Parameter(title: "Question", requestValueDialog: "What do you want to ask?")
    var prompt: String

    @MainActor
    func perform() async throws -> some IntentResult {
        // The OS constructs AppIntent values outside the SwiftUI dependency environment.
        IntentInbox.shared.submit(prompt)
        return .result()
    }
}

struct DSHShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskDSHIntent(),
                    phrases: ["Ask \(.applicationName)", "Ask \(.applicationName) a question", "问 \(.applicationName)"],
                    shortTitle: "Ask DSH",
                    systemImageName: "sparkles")
    }
}

/// Prompts that arrived through App Intents, waiting for a connected chat.
@MainActor
final class IntentInbox {
    static let shared = IntentInbox()
    private(set) var pending: [String] = []
    private var submission: AsyncStream<Void>.Continuation?

    func submissions() -> AsyncStream<Void> {
        AsyncStream { continuation in
            submission?.finish()
            submission = continuation
        }
    }

    func submit(_ prompt: String) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 16384 else { return }
        pending.append(text)
        submission?.yield(())
    }

    func take() -> String? { pending.isEmpty ? nil : pending.removeFirst() }
}
