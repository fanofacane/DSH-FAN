// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/theme/{oklch,accent,palette}.dart. OKLab matrices by Björn Ottosson.
import Foundation
import SwiftUI
import UIKit

struct OKLabTone {
    var lightness: Double
    var chroma: Double
    var hue: Double // radians

    init(lightness: Double, chroma: Double, hue: Double) {
        self.lightness = lightness
        self.chroma = chroma
        self.hue = hue
    }

    init(argb: UInt32) {
        let (r, g, b) = Self.linearRGB(argb)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bAxis = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        chroma = hypot(a, bAxis)
        hue = atan2(bAxis, a)
    }

    var argb: UInt32 {
        func linear(_ chroma: Double) -> [Double] {
            let a = chroma * cos(hue)
            let b = chroma * sin(hue)
            let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
            let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
            let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
            return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s]
        }
        func fits(_ components: [Double]) -> Bool { components.allSatisfy { (-0.0001...1.0001).contains($0) } }
        var components = linear(chroma)
        if !fits(components) {
            var lower = 0.0, upper = chroma
            for _ in 0..<24 {
                let middle = (lower + upper) / 2
                if fits(linear(middle)) { lower = middle } else { upper = middle }
            }
            components = linear(lower)
        }
        return components.reduce(UInt32(255)) { result, linear in
            let gamma = linear <= 0.0031308 ? 12.92 * linear : 1.055 * pow(linear, 1 / 2.4) - 0.055
            return (result << 8) | UInt32((min(1, max(0, gamma)) * 255).rounded())
        }
    }

    func guarded(surface: UInt32, foreground: UInt32, dark: Bool) -> UInt32 {
        func fits(_ color: UInt32) -> Bool {
            Self.contrast(color, surface) >= 3 && Self.contrast(color, foreground) >= 4.5
        }
        if fits(argb) { return argb }
        var candidate = self
        var pass = dark ? 1.0 : 0.0
        var fail = lightness
        for _ in 0..<24 {
            candidate.lightness = (pass + fail) / 2
            if fits(candidate.argb) { pass = candidate.lightness } else { fail = candidate.lightness }
        }
        candidate.lightness = pass
        return candidate.argb
    }

    static func retint(_ argb: UInt32, hue: Double, chroma: Double) -> UInt32 {
        if hue == 266 && chroma == 1 { return argb }
        var tone = Self(argb: argb)
        tone.hue += (hue - 266) * .pi / 180
        tone.chroma *= chroma
        return tone.argb
    }

    private static func linearRGB(_ argb: UInt32) -> (Double, Double, Double) {
        func channel(_ shift: Int) -> Double {
            let v = Double((argb >> shift) & 255) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return (channel(16), channel(8), channel(0))
    }

    private static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ value: UInt32) -> Double {
            let (r, g, b) = linearRGB(value)
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}

extension Color {
    var opaqueARGB: UInt32? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return [r, g, b].reduce(UInt32(255)) { ($0 << 8) | UInt32((min(1, max(0, $1)) * 255).rounded()) }
    }
}
