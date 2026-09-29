import CoreGraphics

/// Geometry for "never in the way": where a note goes so it doesn't hide the
/// text you're typing behind it.
public enum NoteDodge {
    /// Space kept clear around the caret — a band around the line being typed,
    /// wider than tall because typing moves the caret sideways.
    public static let caretClearance = CGSize(width: 90, height: 14)
    /// Gap left between a dodged note and the clear zone.
    public static let gap: CGFloat = 8
    /// Seconds the caret must stay continuously clear of a note's home before it slides back.
    public static let returnDelay: Double = 1.0
    /// Sideways escapes cost more than vertical ones: typing keeps moving along the line.
    static let horizontalPenalty: CGFloat = 1.6

    /// The area around the caret that notes should keep off.
    public static func clearZone(aroundCaret caret: CGRect) -> CGRect {
        caret.insetBy(dx: -caretClearance.width, dy: -caretClearance.height)
    }

    public static func isObstructing(_ frame: CGRect, caret: CGRect) -> Bool {
        frame.intersects(clearZone(aroundCaret: caret))
    }

    /// The frame closest to `home` that leaves the caret's zone clear and stays
    /// inside `visibleFrame`. Returns `home` if it's already clear, or nil if the
    /// note can't get out of the way (then it should fade instead).
    public static func escapeFrame(for home: CGRect, avoidingCaret caret: CGRect, within visibleFrame: CGRect) -> CGRect? {
        let zone = clearZone(aroundCaret: caret)
        guard home.intersects(zone) else { return home }

        let candidates: [(frame: CGRect, penalty: CGFloat)] = [
            (home.offsetBy(dx: 0, dy: zone.maxY + gap - home.minY), 1),                // above the line
            (home.offsetBy(dx: 0, dy: zone.minY - gap - home.maxY), 1),                // below the line
            (home.offsetBy(dx: zone.minX - gap - home.maxX, dy: 0), horizontalPenalty), // left of the caret
            (home.offsetBy(dx: zone.maxX + gap - home.minX, dy: 0), horizontalPenalty), // right of the caret
        ]
        func cost(_ frame: CGRect, _ penalty: CGFloat) -> CGFloat {
            hypot(frame.minX - home.minX, frame.minY - home.minY) * penalty
        }
        return candidates
            .map { (frame: NoteGeometry.fit($0.frame, inside: visibleFrame), penalty: $0.penalty) }
            .filter { $0.frame.size == home.size && !$0.frame.intersects(zone) }
            .min { cost($0.frame, $0.penalty) < cost($1.frame, $1.penalty) }?
            .frame
    }

    /// Accessibility sometimes reports junk (zero rects, whole-document bounds).
    /// Only caret-sized rects are trusted.
    public static func isPlausibleCaret(_ rect: CGRect) -> Bool {
        guard !rect.isNull, rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite else { return false }
        return rect.height > 0 && rect.height <= 200 && rect.width >= 0 && rect.width <= 400
            && rect.origin != .zero
    }
}

public enum ScreenSpace {
    /// Converts a rect from Accessibility/Quartz global coordinates (origin at the
    /// top-left of the primary display, y down) to AppKit's (bottom-left, y up).
    public static func appKitRect(fromTopLeft rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
