import UIKit
#if !SHARE_EXTENSION
import StoreKit
#endif

/// Asks for an App Store rating right after something went well: a card or link was shared, or a card
/// was saved to Photos. Only once someone has done that a few times over a few days, at most once per
/// version and a few months apart. The system still decides whether the rating sheet actually shows
/// (and never more than three times a year).
///
/// Successes are counted in the app group, so shares made from the share extension count too; the
/// request itself is only made in the app, since extensions can't show the rating sheet.
struct ReviewPrompt {
    static let requiredSuccesses = 3
    static let minimumDaysOfUse = 3
    static let minimumDaysBetweenRequests = 120

    enum Key {
        static let successes = "reviewSuccessCount"
        static let firstUse = "reviewFirstUse"
        static let lastRequest = "reviewLastRequest"
        static let lastRequestVersion = "reviewLastRequestVersion"
    }

    var defaults: UserDefaults = AppGroup.defaults
    var version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    var now: () -> Date = Date.init

    var successes: Int { defaults.integer(forKey: Key.successes) }

    func recordFirstUse() {
        if defaults.object(forKey: Key.firstUse) == nil { defaults.set(now(), forKey: Key.firstUse) }
    }

    func recordSuccess() {
        recordFirstUse()
        defaults.set(successes + 1, forKey: Key.successes)
    }

    var isDue: Bool {
        guard successes >= Self.requiredSuccesses,
              let firstUse = defaults.object(forKey: Key.firstUse) as? Date,
              now().timeIntervalSince(firstUse) >= Self.days(Self.minimumDaysOfUse)
        else { return false }
        if defaults.string(forKey: Key.lastRequestVersion) == version { return false }
        if let last = defaults.object(forKey: Key.lastRequest) as? Date,
           now().timeIntervalSince(last) < Self.days(Self.minimumDaysBetweenRequests) {
            return false
        }
        return true
    }

    func markRequested() {
        defaults.set(now(), forKey: Key.lastRequest)
        defaults.set(version, forKey: Key.lastRequestVersion)
    }

    private static func days(_ count: Int) -> TimeInterval { TimeInterval(count) * 24 * 60 * 60 }

    /// Records a success and, when it's time, asks for a rating once the share sheet or notice has settled.
    static func success(in scene: UIWindowScene?) {
        let prompt = ReviewPrompt()
        prompt.recordSuccess()
        #if !SHARE_EXTENSION
        guard prompt.isDue, let scene else { return }
        prompt.markRequested()
        Task {
            try? await Task.sleep(for: .seconds(1))
            AppStore.requestReview(in: scene)
        }
        #endif
    }
}
