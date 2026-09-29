import CoreGraphics
import Foundation

/// sRGB color components in the 0...1 range.
public struct RGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public enum NoteColor: String, Codable, CaseIterable, Sendable {
    case yellow, blue, green, pink, purple, gray

    public var displayName: String { rawValue.capitalized }

    /// Color of the writing area.
    public var body: RGB {
        switch self {
        case .yellow: RGB(1.000, 0.957, 0.635)
        case .blue: RGB(0.788, 0.902, 1.000)
        case .green: RGB(0.800, 0.957, 0.753)
        case .pink: RGB(1.000, 0.824, 0.886)
        case .purple: RGB(0.878, 0.827, 1.000)
        case .gray: RGB(0.929, 0.929, 0.918)
        }
    }

    /// Slightly deeper tone used for the drag bar.
    public var header: RGB {
        switch self {
        case .yellow: RGB(0.992, 0.906, 0.463)
        case .blue: RGB(0.659, 0.835, 0.992)
        case .green: RGB(0.678, 0.906, 0.620)
        case .pink: RGB(0.988, 0.710, 0.812)
        case .purple: RGB(0.800, 0.722, 0.988)
        case .gray: RGB(0.855, 0.855, 0.839)
        }
    }
}

public struct Note: Codable, Identifiable, Equatable, Sendable {
    public static let defaultSize = CGSize(width: 260, height: 220)
    public static let opacityLevels: [Double] = [1.0, 0.85, 0.7, 0.5]
    public static let minimumOpacity = 0.3

    public var id: UUID
    /// Keyed-archived `NSAttributedString`. Archiving (rather than RTF) keeps
    /// system fonts intact across launches. Empty means "use `plainText`".
    public var richText: Data
    /// Plain-text mirror of the note, used for titles and as a fallback.
    public var plainText: String
    /// Expanded frame in global screen coordinates (origin bottom-left).
    /// When collapsed, the note shows only the top strip of this frame.
    public var frame: CGRect
    public var color: NoteColor
    public var opacity: Double
    public var isCollapsed: Bool
    public var createdAt: Date
    public var modifiedAt: Date

    /// "Keep Fresh": nudge now and then so the note isn't tuned out.
    public var keepFresh: Bool
    /// When the nudge schedule started (turned on, or last edited).
    public var freshAnchor: Date?
    public var lastNudge: Date?
    public var nudgeCount: Int
    /// Which shade of its color the note currently shows (0 = standard).
    public var shadeVariant: Int

    public init(
        id: UUID = UUID(),
        richText: Data = Data(),
        plainText: String = "",
        frame: CGRect = CGRect(origin: .zero, size: Note.defaultSize),
        color: NoteColor = .yellow,
        opacity: Double = 1,
        isCollapsed: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        keepFresh: Bool = false,
        freshAnchor: Date? = nil,
        lastNudge: Date? = nil,
        nudgeCount: Int = 0,
        shadeVariant: Int = 0
    ) {
        self.id = id
        self.richText = richText
        self.plainText = plainText
        self.frame = frame
        self.color = color
        self.opacity = Self.clampOpacity(opacity)
        self.isCollapsed = isCollapsed
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.keepFresh = keepFresh
        self.freshAnchor = freshAnchor
        self.lastNudge = lastNudge
        self.nudgeCount = nudgeCount
        self.shadeVariant = shadeVariant
    }

    public var title: String { Self.title(for: plainText) }

    public var isBlank: Bool {
        plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// First non-empty line, trimmed and shortened for menus and collapsed notes.
    public static func title(for text: String, maxLength: Int = 40) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line = firstLine else { return "Empty Note" }
        guard line.count > maxLength else { return line }
        return line.prefix(maxLength - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The next step in the opacity cycle (wraps back to fully opaque).
    public static func nextOpacity(after current: Double) -> Double {
        let index = opacityLevels.firstIndex { abs($0 - current) < 0.01 } ?? (opacityLevels.count - 1)
        return opacityLevels[(index + 1) % opacityLevels.count]
    }

    static func clampOpacity(_ value: Double) -> Double {
        min(max(value, minimumOpacity), 1)
    }

    // MARK: Codable — tolerant of missing/unknown fields so older or hand-edited
    // files still load.

    private enum CodingKeys: String, CodingKey {
        case id, richText, plainText, frame, color, opacity, isCollapsed, createdAt, modifiedAt
        case keepFresh, freshAnchor, lastNudge, nudgeCount, shadeVariant
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        richText = try c.decodeIfPresent(Data.self, forKey: .richText) ?? Data()
        plainText = try c.decodeIfPresent(String.self, forKey: .plainText) ?? ""
        frame = try c.decodeIfPresent(CGRect.self, forKey: .frame) ?? CGRect(origin: .zero, size: Self.defaultSize)
        color = (try? c.decodeIfPresent(NoteColor.self, forKey: .color)) ?? .yellow
        opacity = Self.clampOpacity(try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1)
        isCollapsed = try c.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        keepFresh = try c.decodeIfPresent(Bool.self, forKey: .keepFresh) ?? false
        freshAnchor = try c.decodeIfPresent(Date.self, forKey: .freshAnchor)
        lastNudge = try c.decodeIfPresent(Date.self, forKey: .lastNudge)
        nudgeCount = try c.decodeIfPresent(Int.self, forKey: .nudgeCount) ?? 0
        shadeVariant = try c.decodeIfPresent(Int.self, forKey: .shadeVariant) ?? 0
    }

    /// Whether a fresh note is due for its next nudge.
    public func isDueForNudge(at now: Date) -> Bool {
        guard keepFresh else { return false }
        return FreshSchedule.isDue(anchor: freshAnchor ?? createdAt, lastNudge: lastNudge, now: now)
    }
}
