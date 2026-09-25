// Rasterizes an SVG into the PNGs of a macOS .iconset directory.
// Usage: swift scripts/render-icon.swift <input.svg> <output.iconset>
// Invoked by scripts/make-icon.sh; not meant to be run by hand.
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let image = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("usage: render-icon.swift <input.svg> <output.iconset>\n".data(using: .utf8)!)
    exit(2)
}
let outDir = args[2]
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// Each base size ships at 1x and 2x, as iconutil expects.
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { exit(1) }
        rep.size = NSSize(width: px, height: px)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: px, height: px),
                   from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(base)x\(base)\(suffix).png"))
    }
}
