// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go pack format: app/lib/pets/pet_pack.dart. ActivityKit displays one pose per update.
import SwiftUI
import UIKit

struct PetActivityArtwork: View {
    let state: DSHActivityAttributes.ContentState.Pet
    let size: CGFloat

    var body: some View {
        if let image = Self.frame(state) {
            Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel(Text("Pet"))
        } else {
            Image(systemName: "pawprint").font(.system(size: size * 0.65))
                .accessibilityLabel(Text("Pet"))
        }
    }

    private struct Manifest: Decodable {
        struct Animation: Decodable {
            struct Frame: Decodable { let i: Int }
            let sheet: String
            let frameW: Int
            let frameH: Int
            let cols: Int
            let frames: [Frame]
        }
        let animations: [String: Animation]
    }

    private static func frame(_ state: DSHActivityAttributes.ContentState.Pet) -> UIImage? {
        guard state.pack == URL(fileURLWithPath: state.pack).lastPathComponent,
              state.pack != ".", state.pack != ".." else { return nil }
        var resources = ["Pets"]
        #if DEBUG
        resources.append("PetsLocal")
        #endif
        for root in resources {
            let path = root + "/" + state.pack
            guard let manifestURL = Bundle.main.url(forResource: "pack", withExtension: "json", subdirectory: path),
                  let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
                  let animation = manifest.animations[state.animation] ?? manifest.animations["idle"],
                  let index = animation.frames.first?.i, index >= 0, animation.cols > 0,
                  animation.frameW > 0, animation.frameH > 0,
                  animation.sheet == URL(fileURLWithPath: animation.sheet).lastPathComponent,
                  let sheet = UIImage(contentsOfFile: manifestURL.deletingLastPathComponent().appendingPathComponent(animation.sheet).path)?.cgImage,
                  index / animation.cols < sheet.height / animation.frameH,
                  index % animation.cols < sheet.width / animation.frameW else { continue }
            let rect = CGRect(x: (index % animation.cols) * animation.frameW, y: (index / animation.cols) * animation.frameH,
                              width: animation.frameW, height: animation.frameH)
            if let crop = sheet.cropping(to: rect) { return UIImage(cgImage: crop) }
        }
        return nil
    }
}
