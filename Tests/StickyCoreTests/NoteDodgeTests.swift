import CoreGraphics
import Testing
@testable import StickyCore

@Suite struct NoteDodgeTests {
    let screen = CGRect(x: 0, y: 70, width: 1440, height: 805)
    let home = CGRect(x: 600, y: 400, width: 260, height: 220) // spans y 400...620

    /// A 2×18 caret, like an I-beam in 14pt text.
    func caret(x: CGFloat, y: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: 2, height: 18)
    }

    @Test func noteAwayFromCaretStaysHome() {
        let farCaret = caret(x: 100, y: 200)
        #expect(!NoteDodge.isObstructing(home, caret: farCaret))
        #expect(NoteDodge.escapeFrame(for: home, avoidingCaret: farCaret, within: screen) == home)
    }

    @Test func caretJustOutsideNoteStillCountsAsBlocked() {
        // The clear zone reaches beyond the caret so the note moves before it covers text.
        let nearby = caret(x: 540, y: 500) // 60pt left of the note
        #expect(NoteDodge.isObstructing(home, caret: nearby))
    }

    @Test func caretNearBottomSendsNoteUp() {
        let low = caret(x: 700, y: 410)
        let escape = try! #require(NoteDodge.escapeFrame(for: home, avoidingCaret: low, within: screen))
        #expect(escape.minX == home.minX, "moves vertically, not sideways")
        #expect(escape.minY > home.minY)
        #expect(!escape.intersects(NoteDodge.clearZone(aroundCaret: low)))
    }

    @Test func caretNearTopSendsNoteDown() {
        let high = caret(x: 700, y: 600)
        let escape = try! #require(NoteDodge.escapeFrame(for: home, avoidingCaret: high, within: screen))
        #expect(escape.minX == home.minX)
        #expect(escape.maxY < home.maxY)
        #expect(!escape.intersects(NoteDodge.clearZone(aroundCaret: high)))
    }

    @Test func escapeStaysOnScreenAndKeepsSize() {
        // Note hugging the top of the screen, caret near its bottom: "up" is off-screen.
        let topNote = CGRect(x: 600, y: 655, width: 260, height: 220)
        let c = caret(x: 700, y: 670)
        let escape = try! #require(NoteDodge.escapeFrame(for: topNote, avoidingCaret: c, within: screen))
        #expect(screen.contains(escape))
        #expect(escape.size == topNote.size)
        #expect(!escape.intersects(NoteDodge.clearZone(aroundCaret: c)))
    }

    @Test func prefersVerticalEvenWhenSidewaysIsSlightlyShorter() {
        // Tall note, caret mid-height near its right edge: moving left is 118pt,
        // moving up is 180pt — but sideways escapes are penalized 1.6× (≈189pt).
        let tallHome = CGRect(x: 600, y: 200, width: 200, height: 300)
        let c = caret(x: 780, y: 340)
        let escape = try! #require(NoteDodge.escapeFrame(for: tallHome, avoidingCaret: c, within: screen))
        #expect(escape.minX == tallHome.minX)
    }

    @Test func impossibleEscapeReturnsNil() {
        let giant = CGRect(x: 0, y: 70, width: 1440, height: 805) // fills the screen
        #expect(NoteDodge.escapeFrame(for: giant, avoidingCaret: caret(x: 700, y: 400), within: screen) == nil)
    }

    @Test func plausibleCaretFilter() {
        #expect(NoteDodge.isPlausibleCaret(CGRect(x: 10, y: 10, width: 1, height: 17)))
        #expect(NoteDodge.isPlausibleCaret(CGRect(x: 10, y: 10, width: 0, height: 17)))
        #expect(!NoteDodge.isPlausibleCaret(.zero))
        #expect(!NoteDodge.isPlausibleCaret(CGRect(x: 0, y: 0, width: 1, height: 17)))
        #expect(!NoteDodge.isPlausibleCaret(CGRect(x: 10, y: 10, width: 1, height: 0)))
        #expect(!NoteDodge.isPlausibleCaret(CGRect(x: 10, y: 10, width: 800, height: 900)), "whole-document bounds")
        #expect(!NoteDodge.isPlausibleCaret(CGRect(x: CGFloat.nan, y: 10, width: 1, height: 17)))
        #expect(!NoteDodge.isPlausibleCaret(.null))
    }

    @Test func flipsTopLeftCoordinatesToAppKit() {
        // Primary screen 982pt tall; a caret 100pt from the top.
        let ax = CGRect(x: 50, y: 100, width: 2, height: 18)
        let appKit = ScreenSpace.appKitRect(fromTopLeft: ax, primaryScreenHeight: 982)
        #expect(appKit == CGRect(x: 50, y: 864, width: 2, height: 18))
        // Round-trips.
        #expect(ScreenSpace.appKitRect(fromTopLeft: appKit, primaryScreenHeight: 982) == ax)
    }
}
