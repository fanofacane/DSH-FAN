// SPDX-License-Identifier: AGPL-3.0-or-later
// Pet pack reader and sprite player; same pack format as 原 Flutter 版 lib/pets/pet_pack.dart
// (Clawd on Desk theme layout). The Deepy whale art is the DSH-TUI mascot, not
// covered by AGPL-3.0 (THIRD_PARTY_NOTICES.md): a development placeholder until rebranding.
import DSHClient
import SwiftUI
import UIKit

struct PetAnimation {
    let name: String
    let frames: [UIImage]
    let durations: [Double] // seconds per frame
    let loop: Bool
    /// Where the frame sits on the canvas, in canvas units.
    let box: CGRect
    var total: Double { durations.reduce(0, +) }
}

final class PetPack {
    let canvas: CGSize
    let anchorX: CGFloat
    let baseline: CGFloat
    let contentBox: CGRect
    let states: [String: [String]]
    let tiers: [String: [(min: Int, anim: String)]]
    let idlePool: [(anim: String, ms: Double)]
    let minDisplay: [String: Double]
    let autoReturn: [String: Double]
    let sleepAfter: Double
    let wake: Double
    let reactions: [String: String]
    private let directory: URL
    private let specs: [String: [String: JSONValue]]
    private var cache: [String: PetAnimation] = [:]

    static let deepyWhale: PetPack? = {
        guard let dir = Bundle.main.url(forResource: "deepy-whale", withExtension: nil) else { return nil }
        return try? PetPack(directory: dir)
    }()

    init(directory: URL) throws {
        let data = try Data(contentsOf: directory.appendingPathComponent("pack.json"))
        guard let json = try JSONValue(data: data).object else { throw CocoaError(.fileReadCorruptFile) }
        func rect(_ any: JSONValue?) -> CGRect {
            let m = any?.object ?? [:]
            return CGRect(x: m["x"]?.double ?? 0, y: m["y"]?.double ?? 0, width: m["w"]?.double ?? 0, height: m["h"]?.double ?? 0)
        }
        let canvasMap = json["canvas"]?.object
        canvas = CGSize(width: canvasMap?["w"]?.double ?? 52, height: canvasMap?["h"]?.double ?? 52)
        let anchor = json["anchor"]?.object
        anchorX = anchor?["x"]?.double ?? 26
        baseline = anchor?["baseline"]?.double ?? 48
        contentBox = rect(json["contentBox"])
        states = json["states"]?.decoded([String: [String]].self) ?? [:]
        tiers = (json["tiers"]?.decoded([String: [[String: JSONValue]]].self) ?? [:]).mapValues { rows in
            rows.compactMap { row in (row["anim"]?.string).map { (row["min"]?.int ?? 1, $0) } }
        }
        let pool = json["idlePool"]?.object
        idlePool = (pool?["anims"]?.decoded([[String: JSONValue]].self) ?? []).compactMap { row in
            (row["anim"]?.string).map { ($0, row["ms"]?.double ?? 3000) }
        }
        let timings = json["timings"]?.object
        minDisplay = (timings?["minDisplay"]?.decoded([String: Double].self) ?? [:]).mapValues { $0 / 1000 }
        autoReturn = (timings?["autoReturn"]?.decoded([String: Double].self) ?? [:]).mapValues { $0 / 1000 }
        wake = (timings?["wakeMs"]?.double ?? 1500) / 1000
        sleepAfter = (json["sleep"]?["afterMs"]?.double ?? 60000) / 1000
        reactions = json["reactions"]?.decoded([String: String].self) ?? [:]
        specs = json["animations"]?.decoded([String: [String: JSONValue]].self) ?? [:]
        self.directory = directory
        self.box = rect
    }
    private let box: (JSONValue?) -> CGRect

    /// Decodes and slices a sheet on first use.
    func animation(_ name: String) -> PetAnimation? {
        if let cached = cache[name] { return cached }
        guard let spec = specs[name], let sheetName = spec["sheet"]?.string,
              let sheet = UIImage(contentsOfFile: directory.appendingPathComponent(sheetName).path)?.cgImage else { return nil }
        let frameW = spec["frameW"]?.int ?? 0, frameH = spec["frameH"]?.int ?? 0, cols = max(1, spec["cols"]?.int ?? 1)
        var frames: [UIImage] = [], durations: [Double] = []
        for frame in spec["frames"]?.decoded([[String: JSONValue]].self) ?? [] {
            let index = frame["i"]?.int ?? 0
            let rect = CGRect(x: (index % cols) * frameW, y: (index / cols) * frameH, width: frameW, height: frameH)
            guard let cropped = sheet.cropping(to: rect) else { continue }
            frames.append(UIImage(cgImage: cropped))
            durations.append((frame["ms"]?.double ?? 50) / 1000)
        }
        guard !frames.isEmpty else { return nil }
        let value = PetAnimation(name: name, frames: frames, durations: durations, loop: spec["loop"]?.bool ?? true, box: box(spec["box"]))
        cache[name] = value
        return value
    }

    /// Integer device pixels per canvas unit for a crisp body of `bodyHeight` points.
    func scale(bodyHeight: CGFloat, displayScale: CGFloat) -> CGFloat {
        let k = max(1, (bodyHeight * displayScale / contentBox.height).rounded())
        return k / displayScale
    }
}

/// Plays one animation on the full canvas; calls `onEnd` after a non-looping pass.
struct PetSpriteView: View {
    let animation: PetAnimation
    let scale: CGFloat
    let canvas: CGSize
    var mirrored = false
    var onEnd: (() -> Void)?
    @State private var started = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let image = animation.frames[frameIndex(at: context.date)]
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: animation.box.width * scale, height: animation.box.height * scale)
                .position(x: (animation.box.midX) * scale, y: animation.box.midY * scale)
                .frame(width: canvas.width * scale, height: canvas.height * scale)
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        }
        .onAppear { started = Date() }
        .task(id: animation.name) {
            started = Date()
            guard !animation.loop, let onEnd else { return }
            try? await Task.sleep(nanoseconds: UInt64(animation.total * 1_000_000_000))
            if !Task.isCancelled { onEnd() }
        }
    }

    private func frameIndex(at date: Date) -> Int {
        if reduceMotion { return 0 }
        var t = date.timeIntervalSince(started)
        let total = animation.total
        if animation.loop, total > 0 { t = t.truncatingRemainder(dividingBy: total) }
        for (index, duration) in animation.durations.enumerated() {
            if t < duration { return index }
            t -= duration
        }
        return animation.frames.count - 1
    }
}
