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
    /// How long to wait after a success, so the share sheet or notice has settled first.
    static let delay: Duration = .seconds(1)

    enum Key {
        /// Each process counts under its own key (`reviewSuccessCount.<bundle id>`), so the app and an
        /// extension saving at the same moment can't overwrite each other's count.
        static let successes = "reviewSuccessCount"
        static let firstUse = "reviewFirstUse"
        static let lastRequest = "reviewLastRequest"
        static let lastRequestVersion = "reviewLastRequestVersion"
    }

    var defaults: UserDefaults = AppGroup.defaults
    var version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    /// Which process is counting: the app or one of its extensions.
    var source: String = Bundle.main.bundleIdentifier ?? "app"
    var now: () -> Date = Date.init

    /// Copying in the share sheet doesn't send anything to anyone, so it isn't a success.
    static func counts(_ activity: UIActivity.ActivityType?) -> Bool {
        activity != .copyToPasteboard
    }

    private var ownKey: String { "\(Key.successes).\(source)" }

    var successes: Int {
        defaults.dictionaryRepresentation().reduce(0) { total, entry in
            entry.key.hasPrefix(Key.successes + ".") ? total + ((entry.value as? Int) ?? 0) : total
        }
    }

    func recordFirstUse() {
        resetFutureDates()
        if storedDate(Key.firstUse) == nil { defaults.set(now(), forKey: Key.firstUse) }
    }

    func recordSuccess() {
        recordFirstUse()
        defaults.set(defaults.integer(forKey: ownKey) + 1, forKey: ownKey)
    }

    var isDue: Bool {
        resetFutureDates()
        guard successes >= Self.requiredSuccesses,
              let firstUse = storedDate(Key.firstUse),
              now().timeIntervalSince(firstUse) >= Self.days(Self.minimumDaysOfUse)
        else { return false }
        if defaults.string(forKey: Key.lastRequestVersion) == version { return false }
        if let last = storedDate(Key.lastRequest),
           now().timeIntervalSince(last) < Self.days(Self.minimumDaysBetweenRequests) {
            return false
        }
        return true
    }

    func markRequested() {
        defaults.set(now(), forKey: Key.lastRequest)
        defaults.set(version, forKey: Key.lastRequestVersion)
    }

    /// Resets stored dates that are in the future, which happens when they were recorded while the
    /// device clock was ahead. Left alone, they would hold the prompt back until the clock caught up.
    private func resetFutureDates() {
        let now = now()
        for key in [Key.firstUse, Key.lastRequest] {
            if let date = storedDate(key), date > now { defaults.set(now, forKey: key) }
        }
    }

    private func storedDate(_ key: String) -> Date? { defaults.object(forKey: key) as? Date }

    private static func days(_ count: Int) -> TimeInterval { TimeInterval(count) * 24 * 60 * 60 }

    /// Records a success and, when it's time, asks for a rating once the share sheet or notice has settled.
    /// The request only counts as made once it's actually sent, so the one ask a version gets isn't spent
    /// while the app is in the background or busy with another sheet.
    func success(in scene: UIWindowScene?) {
        recordSuccess()
        #if !SHARE_EXTENSION
        guard isDue, let scene else { return }
        Task {
            try? await Task.sleep(for: Self.delay)
            guard Self.isIdle(scene), isDue else { return }
            markRequested()
            AppStore.requestReview(in: scene)
        }
        #endif
    }

    /// The scene is in front, and nothing it shows is a share sheet, an alert or a sheet on its way in or out.
    static func isIdle(_ scene: UIWindowScene) -> Bool {
        guard scene.activationState == .foregroundActive,
              let root = scene.keyWindow?.rootViewController
        else { return false }
        var controller: UIViewController? = root
        while let current = controller {
            if current is UIActivityViewController || current is UIAlertController
                || current.isBeingPresented || current.isBeingDismissed {
                return false
            }
            controller = current.presentedViewController
        }
        return true
    }
}
