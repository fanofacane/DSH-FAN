// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/pets/{pet_pack,pet_sheets}.dart and ui/pets/pet_sprite.dart.
// The art is a development placeholder. See THIRD_PARTY_NOTICES.md.
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

final class PetPack: Identifiable {
    let id: String
    let name: String
    let pixelArt: Bool
    var displayName: String {
        switch id {
        case "deepy-whale": String(localized: "Deepy the whale")
        case "whale-girl": String(localized: "Whale Girl")
        default: name
        }
    }

    struct Idle {
        let name: String
        let duration: TimeInterval
        let weight: Double
    }

    let canvas: CGSize
    let anchorX: CGFloat
    let baseline: CGFloat
    let contentBox: CGRect
    let states: [String: [String]]
    let tiers: [String: [(min: Int, anim: String)]]
    let idlePool: [Idle]
    let idleEvery: (mean: Double, min: Double, max: Double)
    let roaming: String?
    let facesFront: Bool
    let defaultHitBox: CGRect
    private let wideHitBox: CGRect
    private let sleepingHitBox: CGRect
    private let hitOverrides: [String: CGRect]
    private let wideAnims: Set<String>
    private let sleepingAnims: Set<String>
    private let bonuses: [String: [String: JSONValue]]

    let minDisplay: [String: Double]
    let autoReturn: [String: Double]
    let sleepAfter: Double
    let wake: Double
    let reactions: [String: String]
    private let directory: URL
    private let specs: [String: [String: JSONValue]]
    private var cache: [String: PetAnimation] = [:]

    static func catalog(bundle: Bundle = .main) -> [PetPack] {
        var roots = ["Pets"]
        #if DEBUG
        roots.append("PetsLocal")
        #endif
        var seen: Set<String> = []
        return roots.flatMap { root -> [PetPack] in
            guard let directory = bundle.url(forResource: root, withExtension: nil),
                  let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
            return contents.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
                guard let pack = try? PetPack(directory: url), seen.insert(pack.id).inserted else { return nil }
                return pack
            }
        }
    }

    init(directory: URL) throws {
        let data = try Data(contentsOf: directory.appendingPathComponent("pack.json"))
        guard let json = try JSONValue(data: data).object else { throw CocoaError(.fileReadCorruptFile) }
        func rect(_ any: JSONValue?) -> CGRect {
            let m = any?.object ?? [:]
            return CGRect(x: m["x"]?.double ?? 0, y: m["y"]?.double ?? 0, width: m["w"]?.double ?? 0, height: m["h"]?.double ?? 0)
        }
        id = json["id"]?.string ?? directory.lastPathComponent
        name = json["name"]?.string ?? id
        pixelArt = json["pixelArt"]?.bool ?? true
        let canvasMap = json["canvas"]?.object
        canvas = CGSize(width: canvasMap?["w"]?.double ?? 52, height: canvasMap?["h"]?.double ?? 52)
        let anchor = json["anchor"]?.object
        anchorX = anchor?["x"]?.double ?? 26
        baseline = anchor?["baseline"]?.double ?? 48
        contentBox = rect(json["contentBox"])
        guard canvas.width > 0, canvas.height > 0, canvas.width <= 2048, canvas.height <= 2048,
              contentBox.width > 0, contentBox.height > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let hitBoxes = json["hitBoxes"]?.object ?? [:]
        defaultHitBox = hitBoxes["default"].map(rect) ?? contentBox
        wideHitBox = hitBoxes["wide"].map(rect) ?? defaultHitBox
        sleepingHitBox = hitBoxes["sleeping"].map(rect) ?? defaultHitBox
        hitOverrides = (hitBoxes["byAnim"]?.object ?? [:]).mapValues { rect($0) }
        wideAnims = Set(hitBoxes["wideAnims"]?.decoded([String].self) ?? [])
        sleepingAnims = Set(hitBoxes["sleepingAnims"]?.decoded([String].self) ?? [])
        bonuses = json["bonus"]?.decoded([String: [String: JSONValue]].self) ?? [:]
        roaming = json["roam"]?["anim"]?.string
        facesFront = json["roam"]?["faces"]?.string == "front"
        states = json["states"]?.decoded([String: [String]].self) ?? [:]
        tiers = (json["tiers"]?.decoded([String: [[String: JSONValue]]].self) ?? [:]).mapValues { rows in
            rows.compactMap { row in (row["anim"]?.string).map { (row["min"]?.int ?? 1, $0) } }
        }
        let pool = json["idlePool"]?.object
        idlePool = (pool?["anims"]?.decoded([[String: JSONValue]].self) ?? []).compactMap { row in
            guard let name = row["anim"]?.string else { return nil }
            return Idle(name: name, duration: (row["ms"]?.double ?? 4800) / 1000,
                        weight: max(0, row["weight"]?.double ?? 1))
        }
        let every = pool?["everyMs"]?.object
        idleEvery = ((every?["mean"]?.double ?? 120000) / 1000,
                     (every?["min"]?.double ?? 45000) / 1000,
                     (every?["max"]?.double ?? 300000) / 1000)
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
              sheetName == URL(fileURLWithPath: sheetName).lastPathComponent,
              let sheet = UIImage(contentsOfFile: directory.appendingPathComponent(sheetName).path)?.cgImage else { return nil }
        let frameW = spec["frameW"]?.int ?? 0, frameH = spec["frameH"]?.int ?? 0, cols = max(1, spec["cols"]?.int ?? 1)
        guard frameW > 0, frameH > 0, frameW <= sheet.width, frameH <= sheet.height else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height)
        var frames: [UIImage] = [], durations: [Double] = []
        for frame in spec["frames"]?.decoded([[String: JSONValue]].self) ?? [] {
            let index = frame["i"]?.int ?? 0
            guard index >= 0, index / cols < sheet.height / frameH, index % cols < sheet.width / frameW else { continue }
            let rect = CGRect(x: (index % cols) * frameW, y: (index / cols) * frameH, width: frameW, height: frameH)
            guard bounds.contains(rect), let cropped = sheet.cropping(to: rect) else { continue }
            frames.append(UIImage(cgImage: cropped))
            durations.append(min(60, max(0.01, (frame["ms"]?.double ?? 50) / 1000)))
        }
        guard !frames.isEmpty else { return nil }
        let value = PetAnimation(name: name, frames: frames, durations: durations, loop: spec["loop"]?.bool ?? true, box: box(spec["box"]))
        cache[name] = value
        return value
    }

    func hitBox(for animation: String) -> CGRect {
        if let rect = hitOverrides[animation] { return rect }
        if sleepingAnims.contains(animation) { return sleepingHitBox }
        if wideAnims.contains(animation) { return wideHitBox }
        return defaultHitBox
    }

    func animationName(for state: PetExpression, tier: Int, random: Bool = true) -> String {
        if let variant = tiers[state.rawValue]?.sorted(by: { $0.min > $1.min }).first(where: { tier >= $0.min }) {
            return variant.anim
        }
        if random, let bonus = bonuses[state.rawValue],
           Double.random(in: 0..<1) < (bonus["chance"]?.double ?? 0),
           let name = bonus["anims"]?.decoded([String].self)?.randomElement() { return name }
        let choices = states[state.rawValue] ?? []
        return (random ? choices.randomElement() : choices.first) ?? states["idle"]?.first ?? "idle"
    }

    func idleDelay() -> TimeInterval {
        let chance = Double.random(in: 0..<1)
        return min(idleEvery.max, max(idleEvery.min, -log1p(-chance) * idleEvery.mean))
    }

    /// Snap art pixels to the physical grid for pixel packs.
    func scale(size: PetSize, displayScale: CGFloat) -> CGFloat {
        guard pixelArt else { return size.height / contentBox.height }
        func pixels(_ size: PetSize) -> CGFloat { max(1, (size.height * displayScale / contentBox.height).rounded()) }
        let small = pixels(.small)
        let medium = max(small + 1, pixels(.medium))
        let large = max(medium + 1, pixels(.large))
        switch size {
        case .small: return small / displayScale
        case .medium: return medium / displayScale
        case .large: return large / displayScale
        }
    }
}

struct PetSpriteView: View {
    let animation: PetAnimation
    let scale: CGFloat
    let canvas: CGSize
    var pixelArt = true
    var mirrored = false
    var frozen = false
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var index = 0

    var body: some View {
        Image(uiImage: animation.frames[min(index, animation.frames.count - 1)])
            .interpolation(pixelArt ? .none : .high)
            .resizable()
            .frame(width: animation.box.width * scale, height: animation.box.height * scale)
            .position(x: animation.box.midX * scale, y: animation.box.midY * scale)
            .frame(width: canvas.width * scale, height: canvas.height * scale)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .accessibilityHidden(true)
            .task(id: frozen || reduceMotion || scenePhase == .background) {
                guard !frozen, !reduceMotion, scenePhase != .background else { return }
                let clock = ContinuousClock()
                var deadline = clock.now
                while !Task.isCancelled {
                    let duration = animation.durations[index]
                    deadline = max(deadline + .seconds(duration), clock.now)
                    do { try await clock.sleep(until: deadline) } catch { return }
                    guard !Task.isCancelled else { return }
                    if index == animation.frames.count - 1 {
                        guard animation.loop else { return }
                        index = 0
                    } else {
                        index += 1
                    }
                }
            }
    }
}
