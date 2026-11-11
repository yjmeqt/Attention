import Foundation
import Testing
import UIKit
@testable import Attention

@MainActor
@Suite("Review prompt")
struct ReviewPromptTests {
    private let day: TimeInterval = 24 * 60 * 60
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func prompt(at date: Date, version: String = "1.0", source: String = "app", defaults: UserDefaults) -> ReviewPrompt {
        ReviewPrompt(defaults: defaults, version: version, source: source, now: { date })
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

    @Test func countsSuccessesFromTheAppAndItsExtensions() {
        let defaults = freshDefaults()
        prompt(at: start, source: "app", defaults: defaults).recordSuccess()
        prompt(at: start, source: "app.share", defaults: defaults).recordSuccess()
        prompt(at: start, source: "app.card-action", defaults: defaults).recordSuccess()
        #expect(prompt(at: start, defaults: defaults).successes == 3)
        #expect(prompt(at: start + 3 * day, defaults: defaults).isDue)
    }

    @Test func futureDatesFromAWrongClockAreResetToNow() {
        let defaults = freshDefaults()
        let ahead = prompt(at: start + 365 * day, defaults: defaults)
        ahead.recordFirstUse()
        ahead.markRequested()
        for _ in 0..<ReviewPrompt.requiredSuccesses { ahead.recordSuccess() }

        // The clock is corrected: the dates count from now instead of a year from now.
        #expect(!prompt(at: start, version: "1.1", defaults: defaults).isDue)
        #expect(prompt(at: start + 120 * day, version: "1.1", defaults: defaults).isDue)
    }

    @Test func onlyCompletedSharesThatSendSomethingCount() {
        let defaults = freshDefaults()
        let library = Library(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), inMemory: true)
        let actions = ItemActions(library: library)
        actions.reviewPrompt = prompt(at: start, defaults: defaults)

        actions.presenter.finished(.message, completed: false)
        actions.presenter.finished(nil, completed: false)
        #expect(actions.reviewPrompt.successes == 0)

        actions.presenter.finished(.copyToPasteboard, completed: true)
        #expect(actions.reviewPrompt.successes == 0)

        actions.presenter.finished(.message, completed: true)
        actions.presenter.finished(UIActivity.ActivityType("com.tencent.xin.sharetimeline"), completed: true)
        #expect(actions.reviewPrompt.successes == 2)
    }
}
