// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/pets/{pet_stage,pet_perch,pet_bubble,pet_menu}.dart.
import SwiftUI

struct PetPerchAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}

struct PetStage: View {
    let perch: CGRect
    var reveal: ((String) -> Void)?
    var fixturePose: PetExpression?
    var fixtureHold: CGSize?
    var fixtureBubble: PetBubbleState?

    @Environment(PetModel.self) private var pet
    @Environment(\.displayScale) private var displayScale
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var space
    @State private var drag: CGSize?
    @State private var menu: Menu?
    @State private var nextMenu: Menu?
    @State private var taps = 0

    private enum Menu: String, Identifiable {
        case actions, picker, settings
        var id: Self { self }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)
            if pet.visible, let pack = pet.pack {
                sprite(pack)
            }
        }
        .coordinateSpace(name: space)
        .sensoryFeedback(.selection, trigger: taps)
        .sheet(item: $menu, onDismiss: showNext) { sheet in
            switch sheet {
            case .actions:
                SettingsSheet(title: "Pet") {
                    if let pack = pet.pack {
                        HStack(spacing: Space.md) {
                            PetPreview(pack: pack, side: 56).frame(width: 56, height: 56)
                            Text(pack.displayName).settingsType(.titleMedium)
                            Spacer()
                        }
                    }
                    SheetGroup {
                        menuRow("Change pet", glyph: AppIcon.swap) { nextMenu = .picker; menu = nil }
                        menuRow("Hide for 1 hour", glyph: .eyeSlash) { pet.hide(); menu = nil }
                        menuRow("Pet settings", glyph: AppIcon.settings) { nextMenu = .settings; menu = nil }
                    }
                }.presentationDetents([.medium])
            case .picker:
                SettingsSheet(title: "Change pet") { PetPicker { menu = nil } }
                    .presentationDetents([.medium])
            case .settings:
                NavigationStack { PetSettingsPage() }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { drag = nil } }
        .onChange(of: pet.preferences.packID) { drag = nil }
    }

    private func showNext() {
        guard let nextMenu else { return }
        self.nextMenu = nil
        menu = nextMenu
    }

    private func menuRow(_ title: LocalizedStringKey, glyph: DshGlyph, action: @escaping () -> Void) -> some View {
        Button(action: action) { SettingsRow(glyph: glyph, title: title) { EmptyView() } }
            .buttonStyle(SettingsPressStyle())
    }

    @ViewBuilder private func sprite(_ pack: PetPack) -> some View {
        let movement = fixtureHold ?? drag
        let holding = movement != nil
        let base = fixturePose.map { pack.animationName(for: $0, tier: 1, random: false) } ?? pet.animationName
        let name = holding ? pack.reactions["drag"] ?? base : base
        if let animation = pack.animation(name) ?? pack.animation(pack.animationName(for: .idle, tier: 0, random: false)) {
            let scale = pack.scale(size: pet.preferences.size, displayScale: displayScale)
            let foot = footPosition(pack, scale: scale, dragX: movement?.width ?? 0)
            let lift = holding ? min(-5, max(-40, -10 + (movement?.height ?? 0) * 0.4)) : 0
            let origin = CGPoint(x: snap(foot - pack.anchorX * scale), y: snap(perch.minY - pack.baseline * scale + lift))
            let hit = pack.hitBox(for: name)
            PetSpriteView(animation: animation, scale: scale, canvas: pack.canvas, pixelArt: pack.pixelArt,
                          mirrored: !holding && pet.mirrored, frozen: fixturePose != nil || fixtureHold != nil || !pet.foreground)
                .id("\(pack.id)-\(name)-\(pet.playID)")
                .offset(x: origin.x, y: origin.y)
                .allowsHitTesting(false)
            Color.clear
                .frame(width: hit.width * scale, height: hit.height * scale)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .named(space))
                    .onChanged { value in
                        if drag == nil { taps += 1 }
                        pet.touch()
                        drag = value.translation
                    }
                    .onEnded { value in
                        let newFoot = footPosition(pack, scale: scale, dragX: value.translation.width)
                        withAnimation(reduceMotion ? nil : AppMotion.standard) {
                            pet.preferences.position = min(1, max(0, (newFoot - perch.minX) / max(1, perch.width)))
                            drag = nil
                        }
                    })
                .onTapGesture { location in
                    if pet.expression == .notification, let target = pet.target, let reveal {
                        taps += 1
                        reveal(target)
                    } else {
                        pet.tap(leftHalf: location.x + hit.minX * scale < pack.anchorX * scale)
                        taps += 1
                    }
                }
                .onLongPressGesture(minimumDuration: 0.45) { pet.touch(); menu = .actions }
                .accessibilityLabel(Text(pack.displayName))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { pet.tap(leftHalf: false) }
                .accessibilityAction(named: Text("Pet settings")) { menu = .settings }
                .offset(x: origin.x + hit.minX * scale, y: origin.y + hit.minY * scale)

            if let bubble = fixtureBubble ?? pet.bubble, !holding && !pet.preferences.quiet {
                PetBubblePosition(foot: foot, head: origin.y + pack.contentBox.minY * scale) {
                    PetBubbleView(bubble: bubble) {
                        pet.dismissBubble()
                        reveal?(bubble.event.session)
                    } dismiss: { pet.dismissBubble() }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                .id(bubble.id)
            }
        }
    }

    private func footPosition(_ pack: PetPack, scale: CGFloat, dragX: CGFloat) -> CGFloat {
        let left = perch.minX + Space.lg + (pack.anchorX - pack.contentBox.minX) * scale
        let right = perch.maxX - Space.lg - (pack.contentBox.maxX - pack.anchorX) * scale
        if right < left { return perch.midX }
        let resting = perch.minX + perch.width * (pet.preferences.position + pet.roamOffset)
        return min(right, max(left, resting + dragX))
    }

    private func snap(_ value: CGFloat) -> CGFloat { (value * displayScale).rounded() / displayScale }
}

private struct PetBubblePosition: Layout {
    let foot: CGFloat
    let head: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let bubble = subviews.first else { return }
        let width = min(260, bounds.width - 2 * Space.lg, bubble.sizeThatFits(.unspecified).width)
        let size = bubble.sizeThatFits(ProposedViewSize(width: width, height: nil))
        let inset = Space.lg + size.width / 2
        bubble.place(at: CGPoint(x: bounds.minX + max(inset, min(bounds.width - inset, foot)),
                                 y: bounds.minY + max(size.height / 2, head - 6 - size.height / 2)),
                     anchor: .center, proposal: ProposedViewSize(size))
    }
}

struct PetBubbleView: View {
    let bubble: PetBubbleState
    let open: () -> Void
    let dismiss: () -> Void

    private var title: String? {
        guard bubble.sessions.count == 1, let raw = bubble.event.title, !raw.isEmpty else { return nil }
        return raw.count > 12 ? String(raw.prefix(12)) + "…" : raw
    }

    private var verb: String {
        let count = bubble.sessions.count
        return switch bubble.event.kind {
        case .done: count > 1 ? String(localized: "\(count) chats finished") : String(localized: "Done")
        case .failed: count > 1 ? String(localized: "\(count) chats failed") : String(localized: "Something went wrong")
        case .approval: count > 1 ? String(localized: "\(count) chats need approval") : String(localized: "Needs approval")
        case .question: count > 1 ? String(localized: "\(count) chats need your answer") : String(localized: "Needs your answer")
        case .stopped: String(localized: "Stopped")
        }
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: Space.sm) {
                StatusDot(tone: bubble.event.kind == .failed ? .error : bubble.event.kind.waits ? .warn : .ok, size: 6)
                HStack(spacing: 0) {
                    if let title {
                        Text(title).foregroundStyle(DS.inkFaint).lineLimit(1)
                        Text(" · ").foregroundStyle(DS.inkFaint)
                    }
                    Text(verb).foregroundStyle(DS.ink).lineLimit(1).layoutPriority(1)
                }
                .settingsType(.labelMedium)
            }
            .padding(.horizontal, Space.md).frame(minHeight: 32)
            .glassCapsule(.chrome)
        }
        .buttonStyle(SettingsPressStyle(scales: true))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityAction(named: Text("Dismiss")) { dismiss() }
        .simultaneousGesture(DragGesture(minimumDistance: 12).onEnded { if $0.translation.height < -16 { dismiss() } })
    }
}
