import Foundation
import Testing
@testable import StickyCore

@Suite struct NoteTests {
    @Test func titleUsesFirstNonEmptyLine() {
        #expect(Note.title(for: "\n\n   Groceries  \nmilk\neggs") == "Groceries")
    }

    @Test func titleForBlankText() {
        #expect(Note.title(for: "") == "Empty Note")
        #expect(Note.title(for: "  \n\t\n ") == "Empty Note")
    }

    @Test func titleIsTruncatedWithEllipsis() {
        let title = Note.title(for: String(repeating: "a", count: 100), maxLength: 10)
        #expect(title == "aaaaaaaaa…")
        #expect(title.count == 10)
    }

    @Test func blankDetection() {
        #expect(Note(plainText: " \n ").isBlank)
        #expect(!Note(plainText: "x").isBlank)
    }

    @Test func opacityCyclesThroughLevelsAndWraps() {
        var value = 1.0
        var seen: [Double] = []
        for _ in Note.opacityLevels {
            value = Note.nextOpacity(after: value)
            seen.append(value)
        }
        #expect(seen == [0.85, 0.7, 0.5, 1.0])
        // An off-list value restarts the cycle at fully opaque.
        #expect(Note.nextOpacity(after: 0.42) == 1.0)
    }

    @Test func opacityIsClampedOnInit() {
        #expect(Note(opacity: 0).opacity == Note.minimumOpacity)
        #expect(Note(opacity: 3).opacity == 1)
    }

    @Test func decodingMinimalJSONUsesDefaults() throws {
        let json = #"{"plainText": "hi"}"#.data(using: .utf8)!
        let note = try NoteStore.decoder.decode(Note.self, from: json)
        #expect(note.plainText == "hi")
        #expect(note.color == .yellow)
        #expect(note.opacity == 1)
        #expect(!note.isCollapsed)
        #expect(note.frame.size == Note.defaultSize)
        #expect(note.richText.isEmpty)
    }

    @Test func unknownColorFallsBackToYellow() throws {
        let json = #"{"color": "chartreuse", "opacity": 0.01}"#.data(using: .utf8)!
        let note = try NoteStore.decoder.decode(Note.self, from: json)
        #expect(note.color == .yellow)
        #expect(note.opacity == Note.minimumOpacity)
    }

    @Test func everyColorHasADistinctDeeperHeader() {
        for color in NoteColor.allCases {
            let body = color.body, header = color.header
            #expect(header.red + header.green + header.blue < body.red + body.green + body.blue)
        }
        #expect(Set(NoteColor.allCases.map(\.displayName)).count == NoteColor.allCases.count)
    }
}
