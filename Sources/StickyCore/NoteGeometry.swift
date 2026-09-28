import CoreGraphics

/// A display, in global screen coordinates (origin bottom-left, y up).
public struct ScreenArea: Equatable, Sendable {
    public var frame: CGRect
    /// The frame minus the menu bar and Dock.
    public var visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

public struct ResizeEdges: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let left = ResizeEdges(rawValue: 1 << 0)
    public static let right = ResizeEdges(rawValue: 1 << 1)
    public static let top = ResizeEdges(rawValue: 1 << 2)
    public static let bottom = ResizeEdges(rawValue: 1 << 3)
}

/// Window-frame math for notes, kept free of AppKit so it can be unit-tested.
public enum NoteGeometry {
    public static let headerHeight: CGFloat = 26
    public static let minimumSize = CGSize(width: 160, height: 90)
    public static let cascadeOffset: CGFloat = 24
    /// Margin used when laying notes out from a screen corner.
    public static let screenInset: CGFloat = 40
    /// How much of the drag bar must be on a screen for a note to count as reachable.
    static let minimumVisibleHeaderWidth: CGFloat = 48

    public static func headerRect(of frame: CGRect, headerHeight: CGFloat = headerHeight) -> CGRect {
        CGRect(x: frame.minX, y: frame.maxY - headerHeight, width: frame.width, height: headerHeight)
    }

    /// The top strip a collapsed note shrinks to.
    public static func collapsed(_ expanded: CGRect, headerHeight: CGFloat = headerHeight) -> CGRect {
        headerRect(of: expanded, headerHeight: headerHeight)
    }

    /// True if enough of the note's drag bar is on some screen that the user can grab it.
    public static func isReachable(_ frame: CGRect, on screens: [ScreenArea], headerHeight: CGFloat = headerHeight) -> Bool {
        let header = headerRect(of: frame, headerHeight: headerHeight)
        let neededWidth = min(minimumVisibleHeaderWidth, frame.width)
        return screens.contains { screen in
            let visible = header.intersection(screen.visibleFrame)
            return !visible.isNull && visible.width >= neededWidth && visible.height >= headerHeight / 2
        }
    }

    /// Leaves reachable frames alone; pulls lost ones (e.g. from an unplugged
    /// monitor) fully onto the most relevant screen.
    public static func clamp(_ frame: CGRect, to screens: [ScreenArea], headerHeight: CGFloat = headerHeight) -> CGRect {
        guard !screens.isEmpty, !isReachable(frame, on: screens, headerHeight: headerHeight) else { return frame }
        return fit(frame, inside: bestScreen(for: frame, among: screens).visibleFrame)
    }

    /// The screen overlapping the frame most, or the nearest one if none overlap.
    public static func bestScreen(for frame: CGRect, among screens: [ScreenArea]) -> ScreenArea {
        precondition(!screens.isEmpty, "bestScreen requires at least one screen")
        func overlap(_ screen: ScreenArea) -> CGFloat {
            let shared = frame.intersection(screen.frame)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        if let best = screens.max(by: { overlap($0) < overlap($1) }), overlap(best) > 0 {
            return best
        }
        func distance(_ screen: ScreenArea) -> CGFloat {
            hypot(screen.frame.midX - frame.midX, screen.frame.midY - frame.midY)
        }
        return screens.min(by: { distance($0) < distance($1) })!
    }

    /// Shrinks the frame if needed, then slides it fully inside `bounds`.
    public static func fit(_ frame: CGRect, inside bounds: CGRect) -> CGRect {
        var result = frame
        result.size.width = min(result.width, bounds.width)
        result.size.height = min(result.height, bounds.height)
        result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - result.width)
        result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - result.height)
        return result
    }

    /// Frame for a new note centred under `point`, with the drag bar under the cursor.
    public static func placement(for size: CGSize, anchoredAt point: CGPoint, in visibleFrame: CGRect) -> CGRect {
        let frame = CGRect(
            x: point.x - size.width / 2,
            y: point.y - size.height + headerHeight / 2,
            width: size.width,
            height: size.height
        )
        return fit(frame, inside: visibleFrame)
    }

    /// Frame for a note opened "next to" an existing one; wraps to the top-left
    /// corner instead of walking off the screen.
    public static func cascaded(from frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        var next = frame.offsetBy(dx: cascadeOffset, dy: -cascadeOffset)
        if next.maxX > visibleFrame.maxX || next.minY < visibleFrame.minY {
            next.origin = CGPoint(
                x: visibleFrame.minX + screenInset,
                y: visibleFrame.maxY - screenInset - frame.height
            )
        }
        return fit(next, inside: visibleFrame)
    }

    /// Lays frames out in a cascade from the top-left of `visibleFrame`.
    public static func gathered(_ frames: [CGRect], in visibleFrame: CGRect) -> [CGRect] {
        let start = CGPoint(x: visibleFrame.minX + screenInset, y: visibleFrame.maxY - screenInset)
        var topLeft = start
        return frames.map { frame in
            var placed = CGRect(x: topLeft.x, y: topLeft.y - frame.height, width: frame.width, height: frame.height)
            if placed.minY < visibleFrame.minY || placed.maxX > visibleFrame.maxX {
                topLeft = start
                placed.origin = CGPoint(x: topLeft.x, y: topLeft.y - frame.height)
            }
            topLeft.x += cascadeOffset
            topLeft.y -= cascadeOffset
            return fit(placed, inside: visibleFrame)
        }
    }

    /// Result of dragging the given edges by `delta` (screen points, y up),
    /// never smaller than `minimum`. The opposite edges stay put.
    public static func resized(_ start: CGRect, edges: ResizeEdges, delta: CGSize, minimum: CGSize = minimumSize) -> CGRect {
        var frame = start
        if edges.contains(.right) {
            frame.size.width = max(minimum.width, start.width + delta.width)
        }
        if edges.contains(.left) {
            let width = max(minimum.width, start.width - delta.width)
            frame.origin.x = start.maxX - width
            frame.size.width = width
        }
        if edges.contains(.top) {
            frame.size.height = max(minimum.height, start.height + delta.height)
        }
        if edges.contains(.bottom) {
            let height = max(minimum.height, start.height - delta.height)
            frame.origin.y = start.maxY - height
            frame.size.height = height
        }
        return frame
    }
}
