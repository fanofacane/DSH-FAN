// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHPhone
import SwiftUI
import UIKit

/// Confirmation for a phone action requested by the model.
struct PhoneConfirmSheet: View {
    @Environment(\.designTheme) private var theme
    @Environment(PhoneController.self) private var phone
    let prompt: PhonePrompt

    var body: some View {
        ZStack {
            AppBackdrop(glow: false)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Glyph(glyph: prompt.name == "handoff" ? DshGlyph.handTap : AppIcon.approval, size: 22)
                        .foregroundStyle(prompt.name == "handoff" ? theme.accent : DS.warn)
                    Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(DS.ink)
                }
                .padding(.top, 24)
                Text(prompt.name == "handoff"
                     ? "Do this yourself, then come back and choose Continue."
                     : "Only allow actions you expect. Denying stops this action.")
                    .type(.bodyMedium).foregroundStyle(DS.inkMuted)
                if !prompt.summary.isEmpty {
                    ScrollView { CodeBlockView(language: prompt.name, code: prompt.summary) }.frame(maxHeight: 260)
                }
                Spacer(minLength: 0)
                VStack(spacing: 10) {
                    if prompt.name == "handoff" {
                        MistButton(title: "Continue") { phone.answer(prompt.id, .once) }
                        MistButton(title: "Stop", kind: .danger) { phone.answer(prompt.id, .reject) }
                    } else {
                        MistButton(title: "Allow once") { phone.answer(prompt.id, .once) }
                        if prompt.allowTask {
                            MistButton(title: "Allow for this task", kind: .secondary) { phone.answer(prompt.id, .task) }
                        }
                        MistButton(title: "Deny", kind: .danger) { phone.answer(prompt.id, .reject) }
                    }
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
        }
        .interactiveDismissDisabled()
        .presentationDetents([.medium, .large])
    }

    private var title: LocalizedStringKey {
        switch prompt.name {
        case "handoff": "Your turn"
        case "open": "Open an app or link?"
        case "intent": "Use a system feature?"
        case "notify": "Send a notification?"
        case "clipboard": "Use the clipboard?"
        case "shortcut": "Run a shortcut?"
        default: "Allow this action?"
        }
    }
}
