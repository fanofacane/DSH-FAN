#!/usr/bin/env python3
"""Make a side-by-side image and a registered difference image using macOS AppKit."""

import argparse
from pathlib import Path
import subprocess
import tempfile


SWIFT = r"""
import AppKit

let args = CommandLine.arguments
func open(_ path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: path])
    }
    return image
}

func context(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func scaled(_ image: CGImage, width: Int, skip: Int) -> CGImage {
    let total = Int((Double(width) * Double(image.height) / Double(image.width)).rounded())
    let result = context(width, max(1, total - skip))
    result.interpolationQuality = .high
    result.draw(image, in: CGRect(x: 0, y: 0, width: width, height: total))
    return result.makeImage()!
}

func write(_ context: CGContext, to path: String) throws {
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path), options: .atomic)
}

let width = Int(args[3])!
let golden = try scaled(open(args[1]), width: width, skip: Int(args[5])!)
let screenshot = try scaled(open(args[2]), width: width, skip: Int(args[6])!)
let height = max(golden.height, screenshot.height)
let bar = 30
let right = width + 2

let sideBySide = context(2 * width + 2, height + bar)
sideBySide.setFillColor(CGColor(gray: 0.12, alpha: 1))
sideBySide.fill(CGRect(x: 0, y: 0, width: sideBySide.width, height: sideBySide.height))
sideBySide.draw(golden, in: CGRect(x: 0, y: height - golden.height, width: width, height: golden.height))
sideBySide.draw(screenshot, in: CGRect(x: right, y: height - screenshot.height, width: width, height: screenshot.height))
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: sideBySide, flipped: false)
let labelStyle: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
    .foregroundColor: NSColor.white,
]
("DSH Go · Golden" as NSString).draw(at: CGPoint(x: 10, y: height + 7), withAttributes: labelStyle)
("DSH Fan · iOS Simulator" as NSString).draw(at: CGPoint(x: right + 10, y: height + 7), withAttributes: labelStyle)
NSGraphicsContext.restoreGraphicsState()
try write(sideBySide, to: args[4])

let diff = context(width, height)
diff.setFillColor(CGColor(gray: 0, alpha: 1))
diff.fill(CGRect(x: 0, y: 0, width: width, height: height))
diff.draw(golden, in: CGRect(x: 0, y: height - golden.height, width: width, height: golden.height))
diff.setBlendMode(.difference)
diff.draw(screenshot, in: CGRect(x: 0, y: height - screenshot.height, width: width, height: screenshot.height))
try write(diff, to: args[7])
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("golden", type=Path)
    parser.add_argument("screenshot", type=Path)
    parser.add_argument("width", type=int, help="Golden's logical width in points")
    parser.add_argument("--phase", required=True)
    parser.add_argument("--name", help="Output stem, defaults to the golden's stem")
    parser.add_argument("--golden-top", type=int, default=0, help="Top points to remove after scaling")
    parser.add_argument("--screenshot-top", type=int, default=0, help="Top points to remove after scaling")
    args = parser.parse_args()
    if not 100 <= args.width <= 2048 or min(args.golden_top, args.screenshot_top) < 0:
        parser.error("Specify a width from 100 to 2048 and nonnegative crops")
    name = args.name or args.golden.stem
    if any(Path(part).name != part or part in ("", ".", "..") for part in (args.phase, name)):
        parser.error("Phase and name must each be a single path component")
    output = Path.home() / ".local/share/dsh-fan-compare" / args.phase
    output.mkdir(parents=True, exist_ok=True)
    side = output / f"{name}.png"
    diff = output / f"{name}-diff.png"
    with tempfile.TemporaryDirectory(prefix="dsh-golden-") as scratch:
        script = Path(scratch) / "compare.swift"
        script.write_text(SWIFT, encoding="utf-8")
        subprocess.run(
            ["xcrun", "swift", str(script), str(args.golden), str(args.screenshot), str(args.width),
             str(side), str(args.golden_top), str(args.screenshot_top), str(diff)],
            check=True,
        )
    print(side)
    print(diff)


if __name__ == "__main__":
    main()
