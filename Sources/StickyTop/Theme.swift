import AppKit
import StickyCore

enum Theme {
    static let cornerRadius: CGFloat = 10
    static let bodyFontSize: CGFloat = 14

    /// Notes are always light paper, so ink is a fixed dark color regardless of
    /// the system appearance.
    static let ink = NSColor(srgbRed: 0.13, green: 0.12, blue: 0.10, alpha: 1)
    static let secondaryInk = NSColor(srgbRed: 0.13, green: 0.12, blue: 0.10, alpha: 0.55)

    static var bodyFont: NSFont { .systemFont(ofSize: bodyFontSize) }

    static var typingAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: ink]
    }

    static func swatch(for color: NoteColor, diameter: CGFloat = 12) -> NSImage {
        NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            color.header.nsColor.setFill()
            circle.fill()
            NSColor(white: 0, alpha: 0.25).setStroke()
            circle.lineWidth = 1
            circle.stroke()
            return true
        }
    }
}

extension RGB {
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
}

/// Converts note text to and from the keyed-archive format stored in `Note.richText`.
enum RichText {
    private static let allowedClasses: [AnyClass] = [
        NSAttributedString.self, NSMutableAttributedString.self, NSFont.self, NSColor.self,
        NSParagraphStyle.self, NSMutableParagraphStyle.self, NSTextTab.self, NSShadow.self,
        NSURL.self, NSString.self, NSNumber.self, NSDictionary.self, NSArray.self,
    ]

    static func archive(_ text: NSAttributedString) -> Data {
        (try? NSKeyedArchiver.archivedData(withRootObject: text, requiringSecureCoding: true)) ?? Data()
    }

    static func unarchive(_ data: Data) -> NSAttributedString? {
        guard !data.isEmpty else { return nil }
        return (try? NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: data)) as? NSAttributedString
    }
}
