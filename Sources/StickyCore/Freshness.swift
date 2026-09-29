import Foundation

/// "Keep Fresh": notes that fight reminder blindness. A note that never changes
/// stops being seen, so a fresh note nudges now and then — on a spaced schedule,
/// never looking or reading quite the same way twice.
public enum FreshSchedule {
    /// Gaps between nudges: close together at first, then settling at every two hours.
    public static let intervals: [TimeInterval] = [15, 30, 60, 120].map { $0 * 60 }

    /// The first scheduled nudge strictly after `time`, for a schedule that began at `anchor`.
    public static func nextNudge(after time: Date, anchor: Date) -> Date {
        var point = anchor
        for gap in intervals {
            point += gap
            if point > time { return point }
        }
        // Past the ramp: repeat the last gap.
        let gap = intervals[intervals.count - 1]
        let steps = (time.timeIntervalSince(point) / gap).rounded(.down) + 1
        return point + steps * gap
    }

    /// Whether a nudge is due. Nudges missed while the Mac slept collapse into one.
    public static func isDue(anchor: Date, lastNudge: Date?, now: Date) -> Bool {
        nextNudge(after: lastNudge ?? anchor, anchor: anchor) <= now
    }
}

/// Wording for the reminder card, rotated so it doesn't become wallpaper too.
public enum NudgeCopy {
    public static let leads = [
        "Still on your list", "Don't forget", "Quick reminder",
        "Still pinned", "Heads up", "Worth another look",
    ]

    public static func lead(forNudge number: Int) -> String {
        leads[((number % leads.count) + leads.count) % leads.count]
    }

    /// How long a note has been around: "5 min", "3 h", "1 day", "4 days".
    public static func age(from start: Date, to now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        if minutes < 60 { return "\(max(1, minutes)) min" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h" }
        let days = hours / 24
        return days == 1 ? "1 day" : "\(days) days"
    }

    /// Accepts a model's rewording of `original` only if it's safe to show:
    /// one short line, keeps every name, number and date, invents nothing new
    /// (no added times, deadlines, people), doesn't claim the task is done, and
    /// actually reads differently. Returns the cleaned line, or nil.
    public static func acceptRewording(_ candidate: String, of original: String) -> String? {
        guard var line = cleanRewording(candidate) else { return nil }
        for label in ["reminder:", "note:", "to-do:", "todo:"] where line.lowercased().hasPrefix(label) {
            line = String(line.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
        }
        guard !line.isEmpty else { return nil }

        let originalWords = Set(words(in: original).map { $0.lowercased() })
        let required = keyTokens(in: original)
        let offered = keyTokens(in: line)
        let lineWords = Set(words(in: line).map { $0.lowercased() })

        guard required.isSubset(of: lineWords) else { return nil }           // dropped a detail
        guard offered.isSubset(of: originalWords) else { return nil }        // invented a detail
        for word in inventedTimeWords where lineWords.contains(word) && !originalWords.contains(word) {
            return nil                                                       // made-up urgency
        }
        for word in completionWords where lineWords.contains(word) && !originalWords.contains(word) {
            return nil                                                       // "done" when it isn't
        }
        guard newContentWords(in: line, comparedTo: original) <= 1 else { return nil } // added a person/object
        guard normalized(line) != normalized(original) else { return nil }   // no fresher than before
        return line
    }

    /// Words the rewording adds (ignoring filler words and forms of the original's
    /// words, like "renewal" for "renew"). One is fine — that's a verb swap such as
    /// "book" → "reserve". More usually means something was made up ("…to the developer").
    static func newContentWords(in line: String, comparedTo original: String) -> Int {
        let originalWords = words(in: original).map { $0.lowercased() }
        func related(_ word: String) -> Bool {
            originalWords.contains { other in
                let length = min(4, word.count, other.count)
                return length >= 3 && word.prefix(length) == other.prefix(length)
            }
        }
        return words(in: line).map { $0.lowercased() }.filter { word in
            !fillerWords.contains(word) && !originalWords.contains(word) && !related(word)
        }.count
    }

    static let fillerWords: Set<String> = [
        "the", "a", "an", "to", "for", "on", "at", "by", "your", "my", "our", "some", "of", "in",
        "with", "from", "about", "regarding", "re", "that", "this", "is", "are", "be", "it",
        "and", "or", "up", "off", "out", "please",
    ]

    static let weekdaysAndMonths: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "mon", "tue", "wed", "thu", "fri", "sat", "sun",
        "january", "february", "march", "april", "may", "june", "july", "august",
        "september", "october", "november", "december",
        "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
    ]
    static let inventedTimeWords: Set<String> = [
        "today", "tomorrow", "tonight", "morning", "afternoon", "evening", "noon",
        "midnight", "asap", "urgent", "urgently", "now", "deadline", "overdue",
    ]
    static let completionWords: Set<String> = ["done", "completed", "finished", "handled", "sorted"]

    /// Words, keeping things like "3pm", "v1.2" and "O'Neil" whole ("3 pm" counts as "3pm").
    static func words(in text: String) -> [String] {
        text.replacingOccurrences(of: #"(\d)\s+([aApP]\.?[mM]\.?)(?![a-zA-Z])"#, with: "$1$2", options: .regularExpression)
            .replacingOccurrences(of: #"(\d)([aApP])\.([mM])\.?"#, with: "$1$2$3", options: .regularExpression)
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: ",;!?()\"“”")))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".:-–—'’")) }
            .filter { !$0.isEmpty }
    }

    /// The details a rewording must keep: numbers, weekdays/months, and capitalized
    /// names (the first word is exempt — it's capitalized anyway).
    static func keyTokens(in text: String) -> Set<String> {
        var tokens = Set<String>()
        for (index, word) in words(in: text).enumerated() {
            let lower = word.lowercased()
            let hasDigit = word.contains { $0.isNumber }
            let isCapitalized = word.first?.isUppercase == true && index > 0
            if hasDigit || weekdaysAndMonths.contains(lower) || isCapitalized {
                tokens.insert(lower)
            }
        }
        return tokens
    }

    static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Tidies a model's reworded reminder into one short line, or nil if unusable.
    public static func cleanRewording(_ raw: String, maxLength: Int = 70) -> String? {
        let line = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let unquoted = line.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'‘’ "))
        guard !unquoted.isEmpty, unquoted.count <= maxLength else { return nil }
        let refusals = ["i can't", "i cannot", "i'm sorry", "as an ai", "i am unable"]
        guard !refusals.contains(where: unquoted.lowercased().contains) else { return nil }
        return unquoted
    }
}

extension NoteColor {
    /// Fresh notes cycle through a few shades of their color at each nudge.
    public static let shadeVariantCount = 3

    public func body(variant: Int) -> RGB { Self.shade(body, variant: variant) }
    public func header(variant: Int) -> RGB { Self.shade(header, variant: variant) }

    /// Variant 0 is the standard color; 1 leans warmer, 2 leans cooler and richer.
    static func shade(_ color: RGB, variant: Int) -> RGB {
        let index = ((variant % shadeVariantCount) + shadeVariantCount) % shadeVariantCount
        guard index != 0 else { return color }
        var hsb = HSB(color)
        switch index {
        case 1:
            hsb.hue -= 0.018
            hsb.saturation = min(1, hsb.saturation * 1.12 + 0.02)
        default:
            hsb.hue += 0.018
            hsb.saturation = min(1, hsb.saturation * 1.08 + 0.02)
            hsb.brightness *= 0.985
        }
        return hsb.rgb
    }
}

/// Minimal HSB ↔ RGB conversion (all components 0...1).
struct HSB: Equatable {
    var hue: Double
    var saturation: Double
    var brightness: Double

    init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
    }

    init(_ rgb: RGB) {
        let maxV = max(rgb.red, rgb.green, rgb.blue)
        let minV = min(rgb.red, rgb.green, rgb.blue)
        let delta = maxV - minV
        var hue = 0.0
        if delta > 0 {
            if maxV == rgb.red {
                hue = ((rgb.green - rgb.blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxV == rgb.green {
                hue = (rgb.blue - rgb.red) / delta + 2
            } else {
                hue = (rgb.red - rgb.green) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        self.init(hue: hue, saturation: maxV == 0 ? 0 : delta / maxV, brightness: maxV)
    }

    var rgb: RGB {
        let h = (hue - hue.rounded(.down)) * 6 // wrap into 0..<1, then sectors
        let c = brightness * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<1: (r, g, b) = (c, x, 0)
        case ..<2: (r, g, b) = (x, c, 0)
        case ..<3: (r, g, b) = (0, c, x)
        case ..<4: (r, g, b) = (0, x, c)
        case ..<5: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return RGB(r + m, g + m, b + m)
    }
}
