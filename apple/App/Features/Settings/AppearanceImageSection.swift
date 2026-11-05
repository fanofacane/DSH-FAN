// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/settings/appearance/{launch_screen_section,wallpaper_section}.dart
// and ui/wallpaper/{wallpaper_preview_page,wallpaper_editor_page}.dart.
import PhotosUI
import SwiftUI

struct AppearanceImageSection: View {
    let kind: AppearanceImageKind
    @Environment(AppPreferences.self) private var preferences
    @Environment(AppearanceImages.self) private var images
    @Environment(\.colorScheme) private var scheme
    @State private var picker = false
    @State private var selected: PhotosPickerItem?
    @State private var loading = false
    @State private var preview = false
    @State private var notice: String?

    private var wallpaper: Bool { kind == .wallpaper }
    private var image: UIImage? { images.image(kind) }
    private var enabled: Bool { image != nil && (wallpaper ? preferences.wallpaperOn : preferences.launchImageOn) }

    var body: some View {
        VStack(spacing: Space.xxs) {
            HStack(alignment: .top, spacing: Space.md) {
                choice(custom: false)
                choice(custom: true)
            }
            .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
            ExpandReveal(open: enabled) {
                VStack(spacing: Space.xxs) {
                    if wallpaper { wallpaperRows }
                    else { launchRows }
                    Button { picker = true } label: { SettingsRow(title: "Replace image") }
                        .buttonStyle(SettingsPressStyle()).disabled(loading)
                }
            }
            Button { preview = true } label: { SettingsRow(title: "Preview") }
                .buttonStyle(SettingsPressStyle())
            BriefNotice(text: $notice).padding(.horizontal, Space.lg)
        }
        .photosPicker(isPresented: $picker, selection: $selected, matching: .images)
        .task(id: selected) { if let selected { await importImage(selected) } }
        .fullScreenCover(isPresented: $preview) {
            if wallpaper { WallpaperPreviewPage() }
            else { LaunchArtwork().overlay(alignment: .topLeading) { ClosePreviewButton() } }
        }
    }

    private func choice(custom: Bool) -> some View {
        Button {
            if custom && image == nil { picker = true }
            else { setEnabled(custom) }
        } label: {
            AppearanceChoice(label: custom ? "Custom" : "Default", selected: custom == enabled, aspect: 0.48) {
                if custom, loading {
                    ProgressView()
                } else if custom, let image {
                    if wallpaper {
                        WallpaperPicture(image: image, framing: preferences.wallpaperFrame,
                                         blur: preferences.wallpaperBlur * 0.25, tint: scheme == .dark ? .black : .white,
                                         amount: scheme == .dark ? preferences.wallpaperDim : preferences.wallpaperLighten)
                    } else {
                        LaunchArtwork(image: image, thumbnail: true)
                    }
                } else if custom {
                    Glyph(glyph: AppIcon.image, size: 24).foregroundStyle(DS.inkFaint)
                } else if wallpaper {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Capsule().fill(DS.segmentThumb).frame(width: 44, height: 12)
                        Capsule().fill(DS.segmentThumb).frame(height: 14)
                        Capsule().fill(DS.segmentThumb).frame(width: 36, height: 10)
                        Spacer()
                        Capsule().fill(DS.segmentThumb).frame(height: 16)
                    }.padding(Space.sm)
                } else {
                    LaunchArtwork(thumbnail: true, forceDefault: true)
                }
            }
            .frame(maxWidth: 102)
        }
        .buttonStyle(SettingsPressStyle(scales: true))
        .disabled(loading)
    }

    private var wallpaperRows: some View {
        @Bindable var preferences = preferences
        return VStack(spacing: Space.xxs) {
            SettingsLink(title: "Adjust position") { WallpaperEditorPage() }
                .settingAnchor("wallpaper-frame")
            WallpaperSlider(title: "Blur", value: $preferences.wallpaperBlur)
            WallpaperSlider(title: scheme == .dark ? "Dim" : "Lighten",
                            value: scheme == .dark ? $preferences.wallpaperDim : $preferences.wallpaperLighten)
        }
    }

    private var launchRows: some View {
        @Bindable var preferences = preferences
        return VStack(spacing: Space.xxs) {
            SettingsSegmentRow(title: "Fit", segments: [.init(true, String(localized: "Fill")), .init(false, String(localized: "Center"))],
                               selection: $preferences.launchFill)
            SettingsRow(title: "Background color") {
                HStack(spacing: Space.sm) {
                    ForEach(["theme", "black", "white"], id: \.self) { value in
                        let color: Color = value == "black" ? .black : value == "white" ? .white : DS.surface
                        Button { preferences.launchBackground = value } label: {
                            Circle().fill(color).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(DS.outline, lineWidth: preferences.launchBackground == value ? 2 : 0.5))
                        }.buttonStyle(.plain)
                            .accessibilityLabel(Text(LocalizedStringKey(value.capitalized)))
                            .accessibilityAddTraits(preferences.launchBackground == value ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func setEnabled(_ value: Bool) {
        if wallpaper { preferences.wallpaperOn = value }
        else { preferences.launchImageOn = value }
    }

    private func importImage(_ item: PhotosPickerItem) async {
        loading = true
        defer { loading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw AppearanceImageError.unreadable }
            guard !Task.isCancelled else { return }
            try images.replace(kind, data: data)
            if wallpaper { preferences.wallpaperFrame = WallpaperFrame() }
            setEnabled(true)
            notice = String(localized: "Image updated")
        } catch AppearanceImageError.tooLarge {
            notice = String(localized: "Choose an image under 15 MB.")
        } catch {
            if !Task.isCancelled { notice = String(localized: "Couldn’t read this image.") }
        }
    }
}

private struct WallpaperSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    @State private var draft: Double?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).settingsType(.setting)
                Spacer()
                Text((draft ?? value).formatted(.percent.precision(.fractionLength(0))))
                    .settingsType(.bodyMedium).foregroundStyle(DS.inkMuted)
            }
            Slider(value: Binding(get: { draft ?? value }, set: { draft = $0 }), in: 0...1) { editing in
                if !editing, let draft { value = draft; self.draft = nil }
            }.tint(DS.inkMuted).accessibilityLabel(Text(title))
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.sm)
    }
}

struct WallpaperEditorPage: View {
    @Environment(AppearanceImages.self) private var images
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var draft = WallpaperFrame()

    var body: some View {
        SettingsPage(title: "Adjust position") {
            if let image = images.wallpaper {
                WallpaperPicture(image: image, framing: draft)
                    .frame(height: 330).clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                    .padding(.bottom, Space.lg)
                SettingsGroup {
                    Slider(value: $draft.zoom, in: 1...5).accessibilityLabel("Zoom").padding(.horizontal, Space.lg)
                    Slider(value: $draft.x, in: -1...1).accessibilityLabel("Horizontal position").padding(.horizontal, Space.lg)
                    Slider(value: $draft.y, in: -1...1).accessibilityLabel("Vertical position").padding(.horizontal, Space.lg)
                }
                MistButton(title: "Save") { preferences.wallpaperFrame = draft; dismiss() }
            }
        }
        .onAppear { draft = preferences.wallpaperFrame }
    }
}

struct WallpaperPreviewPage: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            ConversationBackdrop()
            VStack(alignment: .leading, spacing: Space.lg) {
                HStack {
                    ClosePreviewButton()
                    VStack(alignment: .leading) {
                        Text("Example conversation").settingsType(.titleSmall)
                        Text("Preview").settingsType(.labelSmall).foregroundStyle(DS.inkFaint)
                    }.padding(.horizontal, Space.lg).padding(.vertical, Space.xs).glassCapsule()
                    Spacer()
                }
                Text("Show me a weekend plan.").type(.body).padding(Space.md)
                    .background(DS.userBubble, in: RoundedRectangle(cornerRadius: Radius.lg))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Label("Checking the calendar", systemImage: "magnifyingglass").settingsType(.bodyMedium)
                    .padding(Space.md).frame(maxWidth: .infinity, alignment: .leading).glass(.card)
                Text("Saturday morning is free. We can start with a walk and keep the afternoon flexible.").type(.body)
                Spacer()
                HStack {
                    Text("Message").foregroundStyle(DS.inkFaint)
                    Spacer()
                    Glyph(glyph: AppIcon.send)
                }.padding(Space.lg).glassCapsule(.chrome)
            }
            .padding(.horizontal, Space.lg)
        }
        .onTapGesture { dismiss() }
    }
}

struct ClosePreviewButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        GlassIconButton(glyph: AppIcon.close, label: "Close", size: 44) { dismiss() }
            .padding(Space.sm)
    }
}

struct LaunchArtwork: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(AppearanceImages.self) private var images
    var image: UIImage?
    var thumbnail = false
    var forceDefault = false

    var body: some View {
        let photo = forceDefault ? nil : image ?? (preferences.launchImageOn ? images.launch : nil)
        GeometryReader { geometry in
            if let photo {
                let fill = preferences.launchFill
                Image(uiImage: photo).resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(background)
                    .clipped()
            } else {
                ZStack {
                    if thumbnail { DS.backdropTop } else { AppBackdrop() }
                    VStack(spacing: thumbnail ? Space.xs : Space.lg) {
                        BrandMark(size: thumbnail ? 30 : 72)
                        Text(verbatim: "DSH Fan").font(.system(size: thumbnail ? 10 : 26, weight: .semibold))
                    }
                }
            }
        }
        .ignoresSafeArea(thumbnail ? [] : .all)
    }

    private var background: Color {
        switch preferences.launchBackground {
        case "black": .black
        case "white": .white
        default: DS.surface
        }
    }
}
