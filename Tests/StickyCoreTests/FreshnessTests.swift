import Foundation
import Testing
@testable import StickyCore

@Suite struct FreshnessTests {
    let anchor = Date(timeIntervalSince1970: 1_700_000_000)
    func minutes(_ m: Double) -> Date { anchor + m * 60 }

    @Test func rampsUpThenSettlesAtTwoHours() {
        // Nudges at +15, +45, +105, +225 min, then every 120 min.
        var t = anchor
        var points: [Double] = []
        for _ in 0..<7 {
            t = FreshSchedule.nextNudge(after: t, anchor: anchor)
            points.append(t.timeIntervalSince(anchor) / 60)
        }
        #expect(points == [15, 45, 105, 225, 345, 465, 585])
    }

    @Test func nextNudgeIsStrictlyAfter() {
        #expect(FreshSchedule.nextNudge(after: minutes(15), anchor: anchor) == minutes(45))
        #expect(FreshSchedule.nextNudge(after: minutes(14.9), anchor: anchor) == minutes(15))
        #expect(FreshSchedule.nextNudge(after: minutes(345), anchor: anchor) == minutes(465))
    }

    @Test func notDueBeforeFirstPoint() {
        #expect(!FreshSchedule.isDue(anchor: anchor, lastNudge: nil, now: minutes(14)))
        #expect(FreshSchedule.isDue(anchor: anchor, lastNudge: nil, now: minutes(15)))
    }

    @Test func missedNudgesWhileAsleepCollapseIntoOne() {
        // Last nudge at +45; Mac slept until +600. One nudge is due now...
        #expect(FreshSchedule.isDue(anchor: anchor, lastNudge: minutes(45), now: minutes(600)))
        // ...and after nudging at +600 the next one is the next future point, not a backlog.
        let next = FreshSchedule.nextNudge(after: minutes(600), anchor: anchor)
        #expect(next == minutes(705))
        #expect(!FreshSchedule.isDue(anchor: anchor, lastNudge: minutes(600), now: minutes(601)))
    }

    @Test func noteDueOnlyWhenKeptFresh() {
        var note = Note(createdAt: anchor)
        #expect(!note.isDueForNudge(at: minutes(60)))
        note.keepFresh = true
        note.freshAnchor = anchor
        #expect(note.isDueForNudge(at: minutes(60)))
        note.lastNudge = minutes(50)
        #expect(!note.isDueForNudge(at: minutes(60)))
        #expect(note.isDueForNudge(at: minutes(105)))
    }

    @Test func leadRotatesAndWraps() {
        let count = NudgeCopy.leads.count
        #expect(NudgeCopy.lead(forNudge: 0) == NudgeCopy.leads[0])
        #expect(NudgeCopy.lead(forNudge: 1) != NudgeCopy.lead(forNudge: 0))
        #expect(NudgeCopy.lead(forNudge: count) == NudgeCopy.leads[0])
        #expect(NudgeCopy.lead(forNudge: -1) == NudgeCopy.leads[count - 1])
    }

    @Test func ageReadsNaturally() {
        #expect(NudgeCopy.age(from: anchor, to: minutes(0.2)) == "1 min")
        #expect(NudgeCopy.age(from: anchor, to: minutes(42)) == "42 min")
        #expect(NudgeCopy.age(from: anchor, to: minutes(185)) == "3 h")
        #expect(NudgeCopy.age(from: anchor, to: minutes(60 * 30)) == "1 day")
        #expect(NudgeCopy.age(from: anchor, to: minutes(60 * 24 * 4 + 5)) == "4 days")
    }

    @Test func rewordingCleanup() {
        #expect(NudgeCopy.cleanRewording("  \"Dentist call still waiting — Friday 3pm\"  ") == "Dentist call still waiting — Friday 3pm")
        #expect(NudgeCopy.cleanRewording("\nRing the dentist about Friday\nExtra line") == "Ring the dentist about Friday")
        #expect(NudgeCopy.cleanRewording("I'm sorry, but I can't help with that.") == nil)
        #expect(NudgeCopy.cleanRewording("   ") == nil)
        #expect(NudgeCopy.cleanRewording(String(repeating: "x", count: 200)) == nil)
    }

    // Real outputs from the on-device model, and whether they're safe to show.
    @Test(arguments: [
        ("Call dentist to reschedule Friday 3pm", "Reschedule Friday 3pm dentist", true),
        ("Renew passport before June 12", "Passport renewal due June 12", true),
        ("Book flights to Denver for Oct 14", "Flight to Denver on Oct 14", true),
        ("Email Sam about the invoice", "Send Sam that invoice", true),
        ("Water the plants", "Water the plants by 10am", false),                         // invented time
        ("Ship v1.2 release notes", "Send v1.2 release notes to the QA team.", false),   // invented team
        ("Email Sam about the invoice", "Email Sam about the invoice due today at 10am", false),
        ("Call dentist to reschedule Friday 3pm", "Dentist appointment rescheduled.", false), // lost day/time
        ("Call dentist to reschedule Friday 3pm", "Call dentist to reschedule Friday 3pm. Pinned for 3 days.", false),
        ("Water the plants", "Water the plants.", false),                                // not fresher
        ("Call Priya", "Priya call done", false),                                        // claims it's done
        ("Pay rent", "Reminder: Rent needs paying", true),                               // label stripped
        ("Water the plants", "Give the plants some water", true),                        // verb swap is fine
        ("Pick up Maya from soccer at 5", "Collect Maya from soccer at 5", true),
        ("Book flights to Denver for Oct 14", "Reserve flights for Denver on Oct 14.", true),
        ("Ship v1.2 release notes", "Send v1.2 release notes to the developer", false),  // invented person
        ("Call dentist to reschedule Friday 3pm", "Call the dentist to reschedule Friday 3 pm appointment.", true), // "3 pm" = "3pm"
        ("Meet Ana at 9 a.m.", "See Ana at 9am", true),
        ("Renew passport before June 12", "Apply for new passport by June 12", false),    // drifted: new + apply
        ("Renew passport before June 12", "Contact passport office by June 12", false),   // drifted: office
    ])
    func rewordingSafety(original: String, candidate: String, accepted: Bool) {
        let result = NudgeCopy.acceptRewording(candidate, of: original)
        #expect((result != nil) == accepted, "\(candidate)")
        if accepted { #expect(!(result ?? "").lowercased().hasPrefix("reminder:")) }
    }

    @Test func shadesAreDistinctReadableAndStable() {
        for color in NoteColor.allCases {
            #expect(color.body(variant: 0) == color.body, "variant 0 is the standard look")
            let shades = (0..<NoteColor.shadeVariantCount).map { color.body(variant: $0) }
            for (i, a) in shades.enumerated() {
                for b in shades[(i + 1)...] {
                    let diff = abs(a.red - b.red) + abs(a.green - b.green) + abs(a.blue - b.blue)
                    #expect(diff > 0.02, "\(color) shades should differ visibly")
                }
                // Paper stays light enough for dark ink.
                #expect(max(a.red, a.green, a.blue) >= 0.85, "\(color) variant \(i) too dark")
                let header = color.header(variant: i)
                #expect(header.red + header.green + header.blue < a.red + a.green + a.blue)
            }
            #expect(color.body(variant: NoteColor.shadeVariantCount) == color.body, "variants wrap")
        }
    }

    @Test func hsbRoundTrips() {
        for color in NoteColor.allCases {
            let back = HSB(color.body).rgb
            #expect(abs(back.red - color.body.red) < 1e-9)
            #expect(abs(back.green - color.body.green) < 1e-9)
            #expect(abs(back.blue - color.body.blue) < 1e-9)
        }
    }

    @Test func oldNotesDecodeWithFreshnessOff() throws {
        let json = #"{"plainText": "legacy", "color": "pink"}"#.data(using: .utf8)!
        let note = try NoteStore.decoder.decode(Note.self, from: json)
        #expect(!note.keepFresh && note.nudgeCount == 0 && note.shadeVariant == 0)
        #expect(note.freshAnchor == nil && note.lastNudge == nil)
    }

    @Test func freshStateRoundTrips() throws {
        let note = Note(createdAt: anchor, keepFresh: true, freshAnchor: minutes(1),
                        lastNudge: minutes(20), nudgeCount: 3, shadeVariant: 2)
        let data = try NoteStore.encoder.encode(note)
        #expect(try NoteStore.decoder.decode(Note.self, from: data) == note)
    }
}
