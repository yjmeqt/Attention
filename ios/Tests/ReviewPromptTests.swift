import Foundation
import Testing
@testable import Attention

@MainActor
@Suite("Review prompt")
struct ReviewPromptTests {
    private let day: TimeInterval = 24 * 60 * 60
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func prompt(at date: Date, version: String = "1.0", defaults: UserDefaults) -> ReviewPrompt {
        ReviewPrompt(defaults: defaults, version: version, now: { date })
    }

    private func freshDefaults() -> UserDefaults {
        let name = "ReviewPromptTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func waitsForEnoughSuccessesAndDays() {
        let defaults = freshDefaults()
        let first = prompt(at: start, defaults: defaults)
        first.recordFirstUse()
        for _ in 0..<ReviewPrompt.requiredSuccesses { first.recordSuccess() }
        // Enough shares, but on the first day.
        #expect(!first.isDue)

        let later = prompt(at: start + 3 * day, defaults: defaults)
        #expect(later.isDue)

        let fewer = freshDefaults()
        let early = prompt(at: start, defaults: fewer)
        early.recordSuccess()
        early.recordSuccess()
        #expect(!prompt(at: start + 30 * day, defaults: fewer).isDue)
    }

    @Test func firstUseIsKeptFromTheFirstLaunch() {
        let defaults = freshDefaults()
        prompt(at: start, defaults: defaults).recordFirstUse()
        let later = prompt(at: start + 2 * day, defaults: defaults)
        later.recordFirstUse()
        for _ in 0..<ReviewPrompt.requiredSuccesses { later.recordSuccess() }
        #expect(prompt(at: start + 3 * day, defaults: defaults).isDue)
    }

    @Test func asksOncePerVersionAndMonthsApart() {
        let defaults = freshDefaults()
        let first = prompt(at: start, defaults: defaults)
        for _ in 0..<ReviewPrompt.requiredSuccesses { first.recordSuccess() }
        let asked = prompt(at: start + 5 * day, defaults: defaults)
        #expect(asked.isDue)
        asked.markRequested()

        #expect(!prompt(at: start + 300 * day, defaults: defaults).isDue)
        // A new version soon after still waits out the gap.
        #expect(!prompt(at: start + 30 * day, version: "1.1", defaults: defaults).isDue)
        #expect(prompt(at: start + 130 * day, version: "1.1", defaults: defaults).isDue)
    }
}
