// Renders the StickyTop app icon into an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try? FileManager.default.removeItem(at: output)
try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Draws a sticky note centred at the origin of the current (already rotated) context.
func drawNote(size: CGFloat, body: NSColor, header: NSColor, lines: Bool) {
    let rect = NSRect(x: -size / 2, y: -size / 2, width: size, height: size)
    let radius = size * 0.06

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
    shadow.shadowBlurRadius = size * 0.06
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.025)
    shadow.set()
    body.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    header.setFill()
    NSRect(x: rect.minX, y: rect.maxY - size * 0.16, width: size, height: size * 0.16).fill()
    if lines {
        color(0x5A4A12, 0.28).setFill()
        let widths: [CGFloat] = [0.72, 0.6, 0.68, 0.42]
        for (index, width) in widths.enumerated() {
            let y = rect.maxY - size * (0.33 + CGFloat(index) * 0.15)
            let bar = NSRect(x: rect.minX + size * 0.12, y: y, width: size * width, height: size * 0.055)
            NSBezierPath(roundedRect: bar, xRadius: size * 0.0275, yRadius: size * 0.0275).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
}

func renderIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    // macOS icon grid: 824pt rounded square inside a 1024 canvas.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowColor = NSColor(white: 0, alpha: 0.3)
    tileShadow.shadowBlurRadius = 20
    tileShadow.shadowOffset = NSSize(width: 0, height: -8)
    tileShadow.set()
    color(0x2B2F77).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x5B6CF0), ending: color(0x2A2C7A))!.draw(in: tilePath, angle: -90)

    let transform = NSAffineTransform()

    // Back note (blue), tilted left.
    NSGraphicsContext.saveGraphicsState()
    transform.translateX(by: 470, yBy: 480)
    transform.rotate(byDegrees: 9)
    transform.concat()
    drawNote(size: 470, body: color(0xC9E6FF), header: color(0xA8D5FD), lines: false)
    NSGraphicsContext.restoreGraphicsState()

    // Front note (yellow), tilted right.
    NSGraphicsContext.saveGraphicsState()
    let front = NSAffineTransform()
    front.translateX(by: 548, yBy: 470)
    front.rotate(byDegrees: -5)
    front.concat()
    drawNote(size: 500, body: color(0xFFF4A2), header: color(0xFDE776), lines: true)

    // Pin on the front note: it's pinned on top of everything.
    let pinCenter = NSPoint(x: 0, y: 205)
    NSGraphicsContext.saveGraphicsState()
    let pinShadow = NSShadow()
    pinShadow.shadowColor = NSColor(white: 0, alpha: 0.4)
    pinShadow.shadowBlurRadius = 14
    pinShadow.shadowOffset = NSSize(width: 6, height: -10)
    pinShadow.set()
    color(0xE5484D).setFill()
    NSBezierPath(ovalIn: NSRect(x: pinCenter.x - 46, y: pinCenter.y - 46, width: 92, height: 92)).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0xFF7A7E), ending: color(0xC62A30))!
        .draw(in: NSBezierPath(ovalIn: NSRect(x: pinCenter.x - 46, y: pinCenter.y - 46, width: 92, height: 92)), angle: -60)
    NSColor(white: 1, alpha: 0.7).setFill()
    NSBezierPath(ovalIn: NSRect(x: pinCenter.x - 24, y: pinCenter.y + 6, width: 26, height: 20)).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for variant in variants {
    try! renderIcon(pixels: variant.pixels).write(to: output.appendingPathComponent("\(variant.name).png"))
}
print("Wrote \(variants.count) icon images to \(output.path)")
