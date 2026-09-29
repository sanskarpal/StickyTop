import Foundation
import StickyCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Rewords a reminder with Apple's on-device model (macOS 26+, Apple Intelligence
/// on), so a nudge reads freshly each time. Never edits the note; runs offline.
enum Rephraser {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            return true
        }
        #endif
        return false
    }

    /// Why rewording is off, for the menu.
    static var unavailableReason: String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return ""
            case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in System Settings"
            case .unavailable(.deviceNotEligible): return "This Mac doesn't support Apple Intelligence"
            case .unavailable(.modelNotReady): return "Apple Intelligence is still downloading"
            default: return "Apple Intelligence isn't available"
            }
        }
        #endif
        return "Needs macOS 26 with Apple Intelligence"
    }

    static let attempts = 3

    /// A safe rewording of a reminder's first line, or nil. Tries a few times;
    /// every candidate must pass `NudgeCopy.acceptRewording` (keeps names, numbers
    /// and dates, invents nothing, doesn't claim it's done, reads differently).
    static func reword(_ reminder: String, variation: Int) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), isAvailable {
            for _ in 0..<attempts {
                let session = LanguageModelSession(instructions: instructions)
                guard let reply = try? await session.respond(to: reminder, options: GenerationOptions(temperature: 0.8)) else {
                    continue
                }
                if let accepted = NudgeCopy.acceptRewording(reply.content, of: reminder) {
                    return accepted
                }
            }
        }
        #endif
        return nil
    }

    /// Tuned on real reminders: the examples teach "same action, new words",
    /// which cut made-up details and meaning drift sharply.
    private static let instructions = """
        You rewrite one sticky-note reminder so it reads freshly while asking for exactly the same action.
        Rules: Keep the same action (use a close synonym at most) and the same thing it applies to. It stays a to-do: \
        an instruction to the reader, never a statement that it happened or is happening. \
        Keep every name, number, date and time exactly as written. Never add times, deadlines, people or places. \
        Use different wording from the original.
        Reply with only the rewritten reminder, under 60 characters, no quotes, no labels.
        Examples:
        Water the plants -> Give the plants some water
        Pick up Sam from school at 5 -> Collect Sam from school at 5
        Book a table for Friday -> Reserve a table for Friday
        Email Priya the Q3 deck -> Send Priya the Q3 deck by email
        Buy milk -> Pick up some milk
        """
}
