// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/lib/ui/chat/{composer,chat_screen}.dart.
import DSHClient
import SwiftUI

struct ChatComposerView: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    @Binding var draft: String
    @Binding var images: [PickedImage]
    @FocusState.Binding var composerFocused: Bool
    let voice: VoiceInput
    let openWorkspace: () -> Void
    let openImages: () -> Void
    let startDictation: () -> Void
    let submit: () -> Void
    var openTrace: (TurnTrace) -> Void
    var openUsage: () -> Void = {}
    var lowBalance: RunBalance?
    var balanceLimit: Double = RunBalance.defaultLimit
    var dismissBalance: () -> Void = {}
    var showsWorkspace = true
    var previewFolded: Bool?
    var previewTodoOpen = false
    var body: some View {
        VStack(spacing: RunLayout.dockGap) {
            if showsWorkspace {
                Button { openWorkspace() } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "folder")
                        Text(verbatim: chat.workspace.workingDirectoryLabel).lineLimit(1).truncationMode(.middle)
                        Image(systemName: "chevron.down")
                    }.type(.bodySmall).foregroundStyle(DS.inkFaint)
                }
                .buttonStyle(.plain)
                .disabled(chat.transcript.busy)
                .accessibilityLabel(Text("New chat location"))
            }
            ComposerPalette(text: $draft)
            SubagentDock()
            TaskDock(openTrace: openTrace, previewFolded: previewFolded, previewTodoOpen: previewTodoOpen)
            if let lowBalance { LowBalanceBanner(balance: lowBalance, limit: balanceLimit, dismiss: dismissBalance) }
            if let approval = chat.requests.currentApproval {
                ApprovalCard(approval: approval)
            }
            if voice.state == .denied || voice.state == .unavailable {
                Text(voice.state == .denied ? "Allow microphone and speech recognition for DSH in Settings to dictate."
                                            : "Speech recognition isn’t available right now.")
                    .type(.bodySmall).foregroundStyle(DS.warn)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(DS.warnContainer.opacity(0.7), in: Capsule())
                    .onTapGesture { voice.resetMessage() }
                    .task { try? await Task.sleep(nanoseconds: 4_000_000_000); voice.resetMessage() }
            }
            VStack(alignment: .leading, spacing: 8) {
                if !images.isEmpty { imageTray }
                HStack(alignment: .bottom, spacing: 8) {
                    Button { openImages() } label: {
                        Glyph(glyph: AppIcon.add, size: 22).foregroundStyle(DS.ink)
                            .frame(width: RunLayout.composerButton, height: RunLayout.composerButton)
                            .background(DS.surfaceHigh.opacity(0.8), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(chat.transcript.busy && !chat.transcript.canSteer)
                    .accessibilityLabel(Text("Add images"))

                    TextField("", text: $draft, prompt: Text(placeholder).foregroundStyle(DS.inkFaint), axis: .vertical)
                        .accessibilityLabel(Text(placeholder))
                        .type(.body)
                        .foregroundStyle(DS.ink)
                        .lineLimit(1...6)
                        .focused($composerFocused)
                        .padding(.vertical, 8)
                        .frame(minHeight: RunLayout.composerButton)

                    if let fraction = chat.control.projection.metrics.fraction, !voice.isActive {
                        ContextRing(fraction: fraction, open: openUsage)
                    }
                    sendKey
                }
            }
            .padding(Space.xs)
            .glass(.chrome, radius: Radius.xl)
        }
        // Deepy stands on the topmost capsule above the input: the approval card
        // when one is showing, otherwise the composer (pet_perch.dart).
        .anchorPreference(key: PetPerchAnchor.self, value: .bounds) { $0 }
        .padding(.horizontal, Space.floatInset)
        .padding(.bottom, 8)
        .frame(maxWidth: Space.readingWidth)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var sendKey: some View {
        if voice.isActive {
            // Listening: tap to finish; the ring follows the microphone level.
            Button { voice.stop() } label: {
                Glyph(glyph: AppIcon.stopGenerating, size: 16).foregroundStyle(DS.onAccent)
                    .frame(width: RunLayout.composerButton, height: RunLayout.composerButton)
                    .background(theme.accent, in: Circle())
                    .overlay(Circle().stroke(theme.accent.opacity(0.35), lineWidth: 3 + CGFloat(voice.level) * 7))
                    .animation(.easeOut(duration: 0.1), value: voice.level)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Stop dictation"))
        } else if showsWorkspace && preferences.voiceInputEnabled && !chat.transcript.busy && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty {
            Button { startDictation() } label: {
                Glyph(glyph: AppIcon.voice, size: 20).foregroundStyle(DS.ink)
                    .frame(width: RunLayout.composerButton, height: RunLayout.composerButton)
                    .background(DS.surfaceHigh, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!chat.transcript.canSend)
            .accessibilityLabel(Text("Dictate"))
        } else if chat.transcript.stopping || (chat.transcript.turnRunning && !hasContent) {
            Button { Task { await chat.transcript.stop() } } label: {
                Group {
                    if chat.transcript.stopping { ProgressView().tint(theme.onAccent) }
                    else { Glyph(glyph: AppIcon.stopGenerating, size: 18).foregroundStyle(theme.onAccent) }
                }
                .frame(width: RunLayout.composerButton, height: RunLayout.composerButton)
                .background(theme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(chat.transcript.stopping || chat.transcript.sending)
            .accessibilityLabel(Text(chat.transcript.stopping ? "Stopping" : "Stop generating"))
        } else {
            let ready = (chat.transcript.canSend || chat.transcript.canSteer) && hasContent
            Button(action: submit) {
                Glyph(glyph: chat.transcript.turnRunning ? AppIcon.steer : AppIcon.send, size: 20)
                    .foregroundStyle(ready ? DS.onAccent : DS.inkGhost)
                    .frame(width: RunLayout.composerButton, height: RunLayout.composerButton)
                    .background(ready ? theme.accent : DS.surfaceHigh, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!ready)
            .accessibilityLabel(Text("Send"))
        }
    }

    private var hasContent: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty
    }

    private var placeholder: LocalizedStringKey {
        if chat.transcript.stopping { return "Stopping" }
        if chat.requests.currentQuestion != nil { return "Needs your answer" }
        if chat.requests.currentApproval != nil { return "Needs approval" }
        if chat.transcript.turnRunning { return "Generating · Type to steer" }
        return "Message DSH…"
    }

    private var imageTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(images) { picked in
                    Image(uiImage: picked.preview)
                        .resizable().scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button { images.removeAll { $0.id == picked.id } } label: {
                                Glyph(glyph: AppIcon.close, size: 12).foregroundStyle(.white)
                                    .frame(width: 20, height: 20).background(.black.opacity(0.55), in: Circle())
                            }
                            .offset(x: 6, y: -6)
                            .accessibilityLabel(Text("Remove image"))
                        }
                }
            }
            .padding(.top, 6).padding(.horizontal, 4)
        }
    }

}
