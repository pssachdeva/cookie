// Rasterizes an SVG into one square PNG, optionally over a solid background.
// Usage: swift scripts/render-png.swift <input.svg> <output.png> <pixels> [background hex]
// Invoked by scripts/make-ios-assets.sh; not meant to be run by hand.
import AppKit

let args = CommandLine.arguments
guard (4...5).contains(args.count), let image = NSImage(contentsOfFile: args[1]), let px = Int(args[3]) else {
    FileHandle.standardError.write("usage: render-png.swift <input.svg> <output.png> <pixels> [hex]\n".data(using: .utf8)!)
    exit(2)
}
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
rep.size = NSSize(width: px, height: px)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
let bounds = NSRect(x: 0, y: 0, width: px, height: px)
if args.count == 5, let hex = UInt32(args[4], radix: 16) {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1).setFill()
    bounds.fill()
}
image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[2]))
