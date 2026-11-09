import Foundation
import Testing
@testable import Attention

@MainActor
@Suite("Search request lifetime")
struct SearchRequestTests {
    @Test func privateScopeAndLockInvalidateContextImmediately() {
        let library = Library(directory: .temporaryDirectory.appending(path: UUID().uuidString), inMemory: true)
        let filter = FeedFilter()
        filter.scope = .locked
        filter.privateUnlocked = true
        let request = SearchRequest()
        let token = request.begin(in: library, filter: filter)
        #expect(request.accepts(token, in: library, filter: filter))
        filter.privateUnlocked = false
        #expect(!request.accepts(token, in: library, filter: filter))
        filter.scope = .all
        #expect(!request.accepts(token, in: library, filter: filter))
    }

    @Test func oldQueryAndResetCannotPublish() {
        let library = Library(directory: .temporaryDirectory.appending(path: UUID().uuidString), inMemory: true)
        let filter = FeedFilter()
        let request = SearchRequest()
        filter.search = "cats"
        let old = request.begin(in: library, filter: filter)
        filter.search = "dogs"
        #expect(!request.accepts(old, in: library, filter: filter))
        let latest = request.begin(in: library, filter: filter)
        #expect(!request.accepts(old, in: library, filter: filter))
        #expect(request.accepts(latest, in: library, filter: filter))
        request.cancel()
        #expect(!request.accepts(latest, in: library, filter: filter))
    }

    @Test func libraryMutationInvalidatesAnswersAndCounts() {
        let library = Library(directory: .temporaryDirectory.appending(path: UUID().uuidString), inMemory: true)
        let item = library.save(.link(URL(string: "https://example.com")!, image: nil))
        let filter = FeedFilter()
        let request = SearchRequest()
        let token = request.begin(in: library, filter: filter)
        library.setPrivate(true, [item])
        #expect(!request.accepts(token, in: library, filter: filter))
        let next = request.begin(in: library, filter: filter)
        library.delete([item])
        #expect(!request.accepts(next, in: library, filter: filter))
    }

    @Test func downloadedFileOutlivesURLSessionTemporaryFile() throws {
        let temp = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try Data("archive".utf8).write(to: temp)
        let staged = try ClipModel.retainDownload(temp)
        defer { try? FileManager.default.removeItem(at: staged) }
        try? FileManager.default.removeItem(at: temp)
        #expect(try Data(contentsOf: staged) == Data("archive".utf8))
    }
}
