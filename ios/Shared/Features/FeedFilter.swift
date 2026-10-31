import Foundation
import Observation

@Observable
final class FeedFilter {
    /// What the feed shows: one of these at a time. Sites and tags narrow the live items only.
    enum Scope: Hashable {
        case all, archived, locked
        case site(String)
        case tag(String)
    }

    var scope: Scope = .all
    /// Set once Face ID succeeds; cleared whenever Private is left or the app goes to the background.
    var privateUnlocked = false
    var search = ""

    var showsPrivate: Bool { scope == .locked }
    var showsArchived: Bool { scope == .archived }
    var isAll: Bool { scope == .all }

    func reset() {
        scope = .all
        privateUnlocked = false
    }

    func contains(_ item: LibraryItem) -> Bool {
        switch scope {
        case .all: Self.isLive(item)
        case .archived: item.isArchived && !item.isPrivate
        // All private items, archived or not: Private is a single list.
        case .locked: privateUnlocked && item.isPrivate
        case let .site(domain): Self.isLive(item) && item.domain == domain
        case let .tag(tag): Self.isLive(item) && item.tags.contains(tag)
        }
    }

    func apply(_ items: [LibraryItem]) -> [LibraryItem] {
        items.filter { contains($0) && $0.matches(search: search) }
    }

    /// Neither archived nor private: the items that sites and tags are counted from.
    static func isLive(_ item: LibraryItem) -> Bool { !item.isArchived && !item.isPrivate }

    /// Each value with how often it occurs, most common first.
    static func counted(_ values: [String]) -> [(value: String, count: Int)] {
        let counts = values.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (value: $0.key, count: $0.value) }
    }

    /// Most common first.
    static func ranked(_ values: [String]) -> [String] { counted(values).map(\.value) }
}
