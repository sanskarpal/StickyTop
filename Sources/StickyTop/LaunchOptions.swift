import AppKit

/// Developer flags:
///
///     StickyTop --data-dir /tmp/sticky-demo            # use a scratch notes folder
///     StickyTop --data-dir /tmp/demo --snapshot /tmp/out  # render notes to PNG, then quit
///     StickyTop --data-dir /tmp/test --self-test          # debug builds: integration test
struct LaunchOptions {
    var dataDirectory: URL?
    var snapshotDirectory: URL?
    var selfTest = false

    init(arguments: [String] = CommandLine.arguments) {
        func value(after flag: String) -> URL? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return URL(fileURLWithPath: (arguments[index + 1] as NSString).expandingTildeInPath, isDirectory: true)
        }
        dataDirectory = value(after: "--data-dir")
        snapshotDirectory = value(after: "--snapshot")
        selfTest = arguments.contains("--self-test")
    }
}

extension NoteWindowController {
    /// Renders the note's own layer tree (no Screen Recording permission needed).
    func snapshotPNG(scale: CGFloat = 2) -> Data? {
        guard let view = panel.contentView, let layer = view.layer else { return nil }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { return nil }
        context.scaleBy(x: scale, y: scale)
        layer.render(in: context)
        return rep.representation(using: .png, properties: [:])
    }
}
