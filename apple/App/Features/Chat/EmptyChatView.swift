// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct EmptyChatView: View {
    @Environment(PetModel.self) private var pet
    let send: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            // One mascot a screen: the still tail fades while the pet stands on the composer.
            WhaleTail(height: 40).opacity(pet.enabled ? 0 : 0.4).padding(.bottom, 12)
            Text(greeting).type(.display).foregroundStyle(DS.ink)
            Text("What would you like to do today?").type(.body).foregroundStyle(DS.inkFaint).padding(.top, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                suggestion(DshGlyph.folder, "Explore workspace",
                           String(localized: "Check what files and projects are in the workspace and give me a brief overview."))
                suggestion(AppIcon.code, "Count words",
                           String(localized: "Write a Python script that finds the 20 most frequent words in a text file, then run it and show me the results."))
                suggestion(AppIcon.terminal, "Start Node.js",
                           String(localized: "Create a Node.js project in the workspace with TypeScript and a minimal unit test."))
                suggestion(DshGlyph.lightbulb, "Rebase or merge",
                           String(localized: "Use a concrete example to explain the difference between git rebase and git merge, and when to use each."))
            }
            .padding(.top, 36)
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
    }

    private var greeting: LocalizedStringKey {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: "Good morning"
        case 11..<13: "Good noon"
        case 13..<18: "Good afternoon"
        case 18..<23: "Good evening"
        default: "It’s late"
        }
    }

    private func suggestion(_ glyph: DshGlyph, _ title: LocalizedStringKey, _ prompt: String) -> some View {
        Button { send(prompt) } label: {
            HStack(spacing: 6) {
                Glyph(glyph: glyph, size: 16).foregroundStyle(DS.inkMuted)
                Text(title).type(.bodyMedium).foregroundStyle(DS.inkMuted).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(DS.surfaceHigh.opacity(0.75), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
