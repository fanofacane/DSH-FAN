// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct ChatComposerView: View {
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
    var body: some View {
        VStack(spacing: 8) {
            Button { openWorkspace() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(verbatim: chat.workspace.workingDirectoryLabel).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.down")
                }.type(.bodySmall).foregroundStyle(DS.inkFaint)
            }.buttonStyle(.plain).disabled(chat.transcript.busy).accessibilityLabel(Text("New chat location"))
            ComposerPalette(text: $draft)
            SubagentDock()
            TaskDock()
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
                            .frame(width: 40, height: 40)
                            .background(DS.surfaceHigh.opacity(0.8), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(chat.transcript.busy)
                    .accessibilityLabel(Text("Add images"))

                    TextField("Message DSH…", text: $draft, axis: .vertical)
                        .type(.body)
                        .foregroundStyle(DS.ink)
                        .lineLimit(1...6)
                        .focused($composerFocused)
                        .padding(.vertical, 8)
                        .frame(minHeight: 40)

                    sendKey
                }
            }
            .padding(8)
            .glass(.chrome, radius: Radius.xl)
        }
        // Deepy stands on the topmost capsule above the input: the approval card
        // when one is showing, otherwise the composer (pet_perch.dart).
        .overlay(alignment: .topLeading) { PetPerch() }
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
                    .frame(width: 40, height: 40)
                    .background(theme.accent, in: Circle())
                    .overlay(Circle().stroke(theme.accent.opacity(0.35), lineWidth: 3 + CGFloat(voice.level) * 7))
                    .animation(.easeOut(duration: 0.1), value: voice.level)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Stop dictation"))
        } else if !chat.transcript.busy && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty {
            Button { startDictation() } label: {
                Glyph(glyph: AppIcon.voice, size: 20).foregroundStyle(DS.ink)
                    .frame(width: 40, height: 40)
                    .background(DS.surfaceHigh, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!chat.transcript.canSend)
            .accessibilityLabel(Text("Dictate"))
        } else if chat.transcript.busy {
            Button { Task { await chat.transcript.stop() } } label: {
                Glyph(glyph: AppIcon.stop, size: 18).foregroundStyle(DS.ink)
                    .frame(width: 40, height: 40)
                    .background(DS.surfaceHigh, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Stop"))
        } else {
            let ready = chat.transcript.canSend && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty)
            Button(action: submit) {
                Glyph(glyph: AppIcon.send, size: 20)
                    .foregroundStyle(ready ? DS.onAccent : DS.inkGhost)
                    .frame(width: 40, height: 40)
                    .background(ready ? theme.accent : DS.surfaceHigh, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!ready)
            .accessibilityLabel(Text("Send"))
        }
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
