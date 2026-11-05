// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/pets/{pet_settings_page,pet_picker,overlay_settings_tile}.dart.
import ActivityKit
import SwiftUI

struct PetSettingsPage: View {
    @Environment(PetModel.self) private var pet

    var body: some View {
        @Bindable var pet = pet
        SettingsPage(title: "Pets") {
            SettingsGroup(footer: "From DSH-TUI") { PetPicker() }
                .settingAnchor("pet-pack")
            ExpandReveal(open: pet.enabled) {
                SettingsGroup {
                    SettingsSegmentRow(title: "Size", segments: PetSize.allCases.map { PillSegment($0, $0.label) },
                                       selection: $pet.preferences.size)
                        .settingAnchor("pet-size")
                    SettingsToggleRow(title: "Quiet mode", subtitle: String(localized: "Animations only, no bubbles"),
                                      isOn: $pet.preferences.quiet)
                        .settingAnchor("pet-quiet")
                    if pet.hidden {
                        Button { pet.unhide() } label: {
                            let value = pet.preferences.hiddenUntil?.formatted(date: .omitted, time: .shortened)
                            SettingsRow(title: "Show now", value: value) { EmptyView() }
                        }.buttonStyle(SettingsPressStyle())
                    }
                }
                PetOutsideSection()
            }
        }
    }
}

struct PetPicker: View {
    @Environment(PetModel.self) private var pet
    @Environment(\.designTheme) private var theme
    var onPick: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            ForEach(pet.packs) { pack in option(id: pack.id, name: pack.displayName, pack: pack) }
            option(id: PetPreferences.none, name: String(localized: "None"), pack: nil)
        }
        .padding(Space.lg)
        .sensoryFeedback(.selection, trigger: pet.preferences.packID)
    }

    private func option(id: String, name: String, pack: PetPack?) -> some View {
        let selected = pet.preferences.packID == id
        return Button {
            pet.select(id)
            onPick?()
        } label: {
            VStack(spacing: Space.sm) {
                GeometryReader { geometry in PetPreview(pack: pack, side: geometry.size.width) }
                    .aspectRatio(1, contentMode: .fit)
                    .background(DS.ink.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(selected ? theme.accent : DS.rule.opacity(0.7), lineWidth: selected ? 2 : 1)
                    }
                Text(name).settingsType(.labelMedium)
                    .lineLimit(1).foregroundStyle(selected ? theme.accent : DS.inkMuted)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SettingsPressStyle(scales: true))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PetPreview: View {
    let pack: PetPack?
    let side: CGFloat
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let top = side * 0.74
        let height = max(6, side * 0.07)
        ZStack(alignment: .topLeading) {
            Capsule().fill(DS.ink.opacity(0.1)).frame(width: side * 0.62, height: height)
                .position(x: side / 2, y: top + height / 2)
            if let pack, let animation = pack.animation(pack.animationName(for: .idle, tier: 0, random: false)) {
                let ideal = pack.scale(size: .medium, displayScale: displayScale)
                let fitting = max(1, floor((top - 4) * displayScale / max(1, pack.baseline - pack.contentBox.minY))) / displayScale
                let scale = pack.pixelArt ? min(ideal, fitting) : side * 0.34 / pack.contentBox.height
                PetSpriteView(animation: animation, scale: scale, canvas: pack.canvas, pixelArt: pack.pixelArt)
                    .offset(x: side / 2 - pack.contentBox.midX * scale, y: top - pack.baseline * scale)
            }
        }
        .frame(width: side, height: side, alignment: .topLeading)
        .clipped()
        .accessibilityHidden(true)
    }
}

struct PetOutsideSection: View {
    @Environment(PetModel.self) private var pet
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var allowed = false
    @State private var showPermission = false

    var body: some View {
        @Bindable var pet = pet
        SettingsGroup {
            SettingsToggleRow(title: "Show outside the app",
                              subtitle: !allowed && pet.preferences.outside ? String(localized: "Not allowed") : nil,
                              isOn: Binding(get: { allowed && pet.preferences.outside }, set: setEnabled))
                .settingAnchor("pet-outside")
            ExpandReveal(open: allowed && pet.preferences.outside) {
                SettingsSegmentRow(title: "When to show", segments: PetOutsideDisplay.allCases.map { PillSegment($0, $0.label) },
                                   selection: $pet.preferences.outsideDisplay)
                    .settingAnchor("pet-outside-when")
            }
            if pet.outsideSnoozed {
                Button { pet.outsideSnoozedUntil = nil } label: {
                    SettingsRow(title: "Hidden for today", value: String(localized: "Restore")) { EmptyView() }
                }.buttonStyle(SettingsPressStyle())
            }
            if let code = pet.outsideError {
                Text("Request failed: \(code)").settingsType(.bodySmall).foregroundStyle(DS.danger)
                    .padding(.horizontal, Space.lg)
            }
        }
        .task(id: scenePhase) {
            #if DEBUG
            if DebugPageRegistry.usesFixture { allowed = true; return }
            #endif
            allowed = ActivityAuthorizationInfo().areActivitiesEnabled
        }
        .sheet(isPresented: $showPermission) {
            RiskNoticeSheet(title: "Allow Live Activities?",
                            message: "iOS shows your pet on the Lock Screen and Dynamic Island while a Live Activity is available.",
                            action: "Open iOS Settings") { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
    }

    private func setEnabled(_ value: Bool) {
        if value && !allowed { showPermission = true; return }
        pet.outsideError = nil
        pet.outsideSnoozedUntil = nil
        pet.preferences.outside = value
    }
}
