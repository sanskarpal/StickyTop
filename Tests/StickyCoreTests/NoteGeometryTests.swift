import CoreGraphics
import Testing
@testable import StickyCore

@Suite struct NoteGeometryTests {
    // A 1440×900 laptop screen with a 25pt menu bar and 70pt Dock, and an
    // external 1920×1080 display to its right.
    let laptop = ScreenArea(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805)
    )
    let external = ScreenArea(
        frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055)
    )

    @Test func reachableNoteIsLeftAlone() {
        let frame = CGRect(x: 100, y: 300, width: 260, height: 220)
        #expect(NoteGeometry.clamp(frame, to: [laptop]) == frame)
    }

    @Test func partlyOffscreenButGrabbableNoteIsLeftAlone() {
        // Most of the note hangs off the left edge, but 60pt of drag bar is visible.
        let frame = CGRect(x: -200, y: 300, width: 260, height: 220)
        #expect(NoteGeometry.clamp(frame, to: [laptop]) == frame)
    }

    @Test func noteOnUnpluggedDisplayMovesBack() {
        let frame = CGRect(x: 2000, y: 500, width: 260, height: 220) // was on the external display
        let clamped = NoteGeometry.clamp(frame, to: [laptop])
        #expect(laptop.visibleFrame.contains(clamped))
        #expect(clamped.size == frame.size)
    }

    @Test func dragBarHiddenUnderMenuBarCountsAsUnreachable() {
        let frame = CGRect(x: 100, y: 700, width: 260, height: 220) // top at 920, above the 875 limit
        let clamped = NoteGeometry.clamp(frame, to: [laptop])
        #expect(clamped.maxY == laptop.visibleFrame.maxY)
        #expect(clamped.minX == 100)
    }

    @Test func picksScreenWithMostOverlap() {
        let frame = CGRect(x: 1400, y: 1000, width: 300, height: 220) // drag bar above both screens
        let clamped = NoteGeometry.clamp(frame, to: [laptop, external])
        #expect(external.visibleFrame.contains(clamped))
    }

    @Test func picksNearestScreenWhenNoOverlap() {
        let frame = CGRect(x: 5000, y: 200, width: 260, height: 220)
        let clamped = NoteGeometry.clamp(frame, to: [laptop, external])
        #expect(external.visibleFrame.contains(clamped))
    }

    @Test func fitShrinksOversizedFrames() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        let fitted = NoteGeometry.fit(CGRect(x: -50, y: -50, width: 500, height: 500), inside: bounds)
        #expect(fitted == bounds)
    }

    @Test func noScreensMeansNoChange() {
        let frame = CGRect(x: 99_999, y: 99_999, width: 10, height: 10)
        #expect(NoteGeometry.clamp(frame, to: []) == frame)
    }

    @Test func placementPutsDragBarUnderPointer() {
        let size = CGSize(width: 260, height: 220)
        let frame = NoteGeometry.placement(for: size, anchoredAt: CGPoint(x: 700, y: 500), in: laptop.visibleFrame)
        #expect(frame.midX == 700)
        #expect(NoteGeometry.headerRect(of: frame).contains(CGPoint(x: 700, y: 500)))
    }

    @Test func placementFromMenuBarStaysBelowIt() {
        let size = CGSize(width: 260, height: 220)
        let frame = NoteGeometry.placement(for: size, anchoredAt: CGPoint(x: 1430, y: 890), in: laptop.visibleFrame)
        #expect(laptop.visibleFrame.contains(frame))
    }

    @Test func cascadeOffsetsDownAndRight() {
        let start = CGRect(x: 100, y: 400, width: 260, height: 220)
        let next = NoteGeometry.cascaded(from: start, in: laptop.visibleFrame)
        #expect(next.origin == CGPoint(x: 124, y: 376))
    }

    @Test func cascadeWrapsInsteadOfLeavingScreen() {
        let start = CGRect(x: 1170, y: 80, width: 260, height: 220)
        let next = NoteGeometry.cascaded(from: start, in: laptop.visibleFrame)
        #expect(laptop.visibleFrame.contains(next))
        #expect(next.minX == laptop.visibleFrame.minX + NoteGeometry.screenInset)
    }

    @Test func gatheredFramesAllLandOnScreen() {
        let frames = (0..<40).map { CGRect(x: Double($0) * 500, y: -900, width: 260, height: 220) }
        let gathered = NoteGeometry.gathered(frames, in: laptop.visibleFrame)
        #expect(gathered.count == frames.count)
        #expect(gathered.allSatisfy { laptop.visibleFrame.contains($0) })
        #expect(gathered[1].minX - gathered[0].minX == NoteGeometry.cascadeOffset)
    }

    @Test func collapsedKeepsTopEdge() {
        let expanded = CGRect(x: 10, y: 100, width: 260, height: 220)
        let collapsed = NoteGeometry.collapsed(expanded)
        #expect(collapsed.maxY == expanded.maxY)
        #expect(collapsed.height == NoteGeometry.headerHeight)
        #expect(collapsed.width == expanded.width)
    }

    @Test(arguments: [
        (ResizeEdges.right, CGSize(width: 40, height: 0), CGRect(x: 100, y: 100, width: 300, height: 200)),
        (ResizeEdges.left, CGSize(width: -40, height: 0), CGRect(x: 60, y: 100, width: 300, height: 200)),
        (ResizeEdges.bottom, CGSize(width: 0, height: -50), CGRect(x: 100, y: 50, width: 260, height: 250)),
        (ResizeEdges.top, CGSize(width: 0, height: 30), CGRect(x: 100, y: 100, width: 260, height: 230)),
        (ResizeEdges([.right, .bottom]), CGSize(width: 10, height: -10), CGRect(x: 100, y: 90, width: 270, height: 210)),
    ])
    func resizeMovesOnlyDraggedEdges(edges: ResizeEdges, delta: CGSize, expected: CGRect) {
        let start = CGRect(x: 100, y: 100, width: 260, height: 200)
        #expect(NoteGeometry.resized(start, edges: edges, delta: delta) == expected)
    }

    @Test func resizeRespectsMinimumAndKeepsOppositeEdge() {
        let start = CGRect(x: 100, y: 100, width: 260, height: 200)
        let shrunk = NoteGeometry.resized(start, edges: [.left, .bottom], delta: CGSize(width: 1000, height: 1000))
        #expect(shrunk.size == NoteGeometry.minimumSize)
        #expect(shrunk.maxX == start.maxX)
        #expect(shrunk.maxY == start.maxY)
    }
}
