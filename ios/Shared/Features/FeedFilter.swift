import Foundation
import Observation

@Observable
final class FeedFilter {
    /// Items from any of these domains (an item has only one).
    var domains: Set<String> = []
    /// Items carrying all of these tags.
    var tags: Set<String> = []
    var showsPrivate = false
    /// Archived items of the current section (private or not) instead of its live ones.
    var showsArchived = false
    /// Set once Face ID succeeds; cleared whenever Private is left or the app goes to the background.
    var privateUnlocked = false
    var search = ""

    var isAll: Bool { domains.isEmpty && tags.isEmpty && !showsPrivate && !showsArchived }

    func reset() {
        domains = []
        tags = []
        showsPrivate = false
        showsArchived = false
        privateUnlocked = false
    }

    /// Clears domain and tag filters, staying in the current section.
    func clearFilters() {
        domains = []
        tags = []
    }

    func only(domain: String) {
        clearFilters()
        domains = [domain]
    }

    func only(tag: String) {
        clearFilters()
        tags = [tag]
    }

    /// Items in the current section (private or not, archived or not), before domain and tag filters.
    func section(_ items: [LibraryItem]) -> [LibraryItem] {
        items.filter { $0.isPrivate == showsPrivate && $0.isArchived == showsArchived }
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
