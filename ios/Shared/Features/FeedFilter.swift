import Foundation
import Observation

@Observable
final class FeedFilter {
    /// Items from any of these domains (an item has only one).
    var domains: Set<String> = []
    /// Items carrying all of these tags.
    var tags: Set<String> = []
    var showsPrivate = false
    /// Set once Face ID succeeds; cleared whenever Private is left or the app goes to the background.
    var privateUnlocked = false
    var search = ""

    var isAll: Bool { domains.isEmpty && tags.isEmpty && !showsPrivate }

    func reset() {
        domains = []
        tags = []
        showsPrivate = false
        privateUnlocked = false
    }

    func only(domain: String) {
        let keepsPrivate = showsPrivate
        reset()
        showsPrivate = keepsPrivate
        domains = [domain]
    }

    func only(tag: String) {
        let keepsPrivate = showsPrivate
        reset()
        showsPrivate = keepsPrivate
        tags = [tag]
    }

    /// Items in the current section (private or not), before domain and tag filters.
    func section(_ items: [LibraryItem]) -> [LibraryItem] {
        items.filter { $0.isPrivate == showsPrivate }
    }

    func apply(_ items: [LibraryItem]) -> [LibraryItem] {
        if showsPrivate && !privateUnlocked { return [] }
        return section(items).filter { item in
            (domains.isEmpty || domains.contains(item.domain))
                && tags.isSubset(of: item.tags)
                && item.matches(search: search)
        }
    }
}
