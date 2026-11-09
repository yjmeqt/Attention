import Foundation
import Observation

/// Captures all inputs whose changes make an answer (including its count) obsolete.
struct SearchContext: Equatable {
    let query: String
    let scope: FeedFilter.Scope
    let privateUnlocked: Bool
    let revision: Int

    init(in library: Library, filter: FeedFilter) {
        query = filter.search
        scope = filter.scope
        privateUnlocked = filter.privateUnlocked
        revision = library.revision
    }
}

@Observable
final class SearchRequest {
    private var token: UUID?
    private var context: SearchContext?

    func begin(in library: Library, filter: FeedFilter) -> UUID {
        let token = UUID()
        self.token = token
        context = SearchContext(in: library, filter: filter)
        return token
    }

    func cancel() {
        token = nil
        context = nil
    }

    func isCurrent(in library: Library, filter: FeedFilter) -> Bool {
        token != nil && context == SearchContext(in: library, filter: filter)
    }

    func accepts(_ token: UUID, in library: Library, filter: FeedFilter) -> Bool {
        !Task.isCancelled && self.token == token && isCurrent(in: library, filter: filter)
    }
}
