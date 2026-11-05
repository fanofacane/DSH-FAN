// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/wallpaper/{custom_wallpaper,wallpaper_import,wallpaper_look,wallpaper_render}.dart
// and lib/ui/wallpaper/wallpaper_backdrop.dart.
import CoreImage
import ImageIO
import SwiftUI

enum AppearanceImageKind: String {
    case launch, wallpaper
}

@MainActor @Observable final class AppearanceImages {
    private let directory: URL
    private(set) var launch: UIImage?
    private(set) var wallpaper: UIImage?
    private(set) var wallpaperAccent: UInt32?

    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("Appearance", isDirectory: true)) {
        self.directory = directory
        launch = UIImage(contentsOfFile: url(for: .launch).path)
        wallpaper = UIImage(contentsOfFile: url(for: .wallpaper).path)
        wallpaperAccent = wallpaper.flatMap(Self.accent)
    }

    func image(_ kind: AppearanceImageKind) -> UIImage? { kind == .launch ? launch : wallpaper }

    private func url(for kind: AppearanceImageKind) -> URL {
        directory.appendingPathComponent(kind.rawValue).appendingPathExtension("jpg")
    }

    func replace(_ kind: AppearanceImageKind, data: Data) throws {
        guard data.count <= 15 * 1024 * 1024 else { throw AppearanceImageError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let picture = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
              ] as CFDictionary) else { throw AppearanceImageError.unreadable }
        let image = UIImage(cgImage: picture)
        guard let stored = image.jpegData(compressionQuality: 0.91) else { throw AppearanceImageError.unreadable }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try stored.write(to: url(for: kind), options: [.atomic, .completeFileProtection])
        if kind == .launch { launch = image }
        else { wallpaper = image; wallpaperAccent = Self.accent(image) }
    }

    private static func accent(_ image: UIImage) -> UInt32? {
        guard let cgImage = image.cgImage else { return nil }
        // Pick the brightest chromatic patch from a tiny downsample; a gray
        // wallpaper retains the average tone as a valid custom seed.
        let size = 8
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        return bytes.withUnsafeMutableBytes { pixels in
            guard let context = CGContext(data: pixels.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                          bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
            let values = pixels.bindMemory(to: UInt8.self)
            var best: (value: UInt32, score: Double)?
            for index in stride(from: 0, to: values.count, by: 4) {
                let value = 0xFF000000 | UInt32(values[index]) << 16 | UInt32(values[index + 1]) << 8 | UInt32(values[index + 2])
                let tone = OKLabTone(argb: value)
                let score = tone.chroma * (1 - abs(tone.lightness - 0.6))
                if best == nil || score > best!.score { best = (value, score) }
            }
            return best?.value
        }
    }

    #if DEBUG
    func seedPreview() {
        let size = CGSize(width: 240, height: 480)
        let example = UIGraphicsImageRenderer(size: size).image { context in
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      colors: [UIColor(red: 0.37, green: 0.24, blue: 0.42, alpha: 1).cgColor,
                                               UIColor(red: 0.91, green: 0.64, blue: 0.39, alpha: 1).cgColor,
                                               UIColor(red: 0.25, green: 0.44, blue: 0.55, alpha: 1).cgColor] as CFArray,
                                      locations: [0, 0.54, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
        launch = example
        wallpaper = example
        wallpaperAccent = Self.accent(example)
    }
    #endif
}

enum AppearanceImageError: Error {
    case tooLarge, unreadable
}

struct WallpaperFrame: Equatable {
    var zoom = 1.0
    var x = 0.0
    var y = 0.0

    func drawRect(image: CGSize, viewport: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0, viewport.width > 0, viewport.height > 0 else { return .zero }
        let scale = max(viewport.width / image.width, viewport.height / image.height) * min(5, max(1, zoom))
        let width = image.width * scale
        let height = image.height * scale
        return CGRect(x: -(width - viewport.width) * (1 + min(1, max(-1, x))) / 2,
                      y: -(height - viewport.height) * (1 + min(1, max(-1, y))) / 2, width: width, height: height)
    }
}

struct ConversationBackdrop: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(AppearanceImages.self) private var images
    @Environment(\.colorScheme) private var scheme
    var frame: WallpaperFrame?

    var body: some View {
        if preferences.wallpaperOn, let image = images.wallpaper {
            WallpaperPicture(image: image, framing: frame ?? preferences.wallpaperFrame, blur: preferences.wallpaperBlur,
                             tint: scheme == .dark ? .black : .white,
                             amount: scheme == .dark ? preferences.wallpaperDim : preferences.wallpaperLighten)
                .ignoresSafeArea()
        } else {
            AppBackdrop()
        }
    }
}

struct WallpaperPicture: View {
    let image: UIImage
    let framing: WallpaperFrame
    var blur = 0.0
    var tint: Color = .clear
    var amount = 0.0

    var body: some View {
        GeometryReader { geometry in
            let rect = framing.drawRect(image: image.size, viewport: geometry.size)
            Image(uiImage: image)
                .resizable().interpolation(.high)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .blur(radius: 22 * blur, opaque: true)
                .overlay(tint.opacity(amount))
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
