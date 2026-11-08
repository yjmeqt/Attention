import Foundation
import Testing
@testable import Attention

@MainActor
@Suite("Search demo corpus")
struct SearchDemoCorpusTests {
    private struct Question: Decodable {
        let id: String
        let scope: String
        let expectedCount: Int
        let site: String?
        let tag: String?
        let sinceHours: Int?
        let keyword: String?
        let visualConcept: String?

        enum CodingKeys: String, CodingKey {
            case id, scope, site, tag, keyword
            case expectedCount = "expected_count"
            case sinceHours = "since_hours"
            case visualConcept = "visual_concept"
        }
    }

    @Test func seedsStableSearchCasesWithoutNetwork() {
        let library = Library(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), inMemory: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(SearchDemoCorpus.seed(into: library, now: now))
        #expect(library.items.count == 204)
        #expect(library.items.filter(\.isImage).count == 12)

        let filter = FeedFilter()
        #expect(filter.apply(library.items).count == 188)

        var github = QueryPlan()
        github.site = "github.com"
        #expect(github.apply(to: library.items.filter(filter.contains), now: now).count == 22)

        github.sinceHours = 24
        #expect(github.apply(to: library.items.filter(filter.contains), now: now).count == 12)

        var programming = QueryPlan()
        programming.tags = ["Programming"]
        #expect(programming.apply(to: library.items.filter(filter.contains), now: now).count == 34)

        filter.scope = .archived
        #expect(filter.apply(library.items).count == 8)
        filter.scope = .locked
        #expect(filter.apply(library.items).isEmpty)
        filter.privateUnlocked = true
        #expect(filter.apply(library.items).count == 8)
    }

    @Test func everyQuestionHasTheExpectedMatchCount() throws {
        let library = Library(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), inMemory: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(SearchDemoCorpus.seed(into: library, now: now))

        let questionsURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Tools/search-demo/questions.json")
        let questions = try JSONDecoder().decode([Question].self, from: Data(contentsOf: questionsURL))
        #expect(questions.count == 112)
        for question in questions {
            let filter = FeedFilter()
            if question.scope == "archived" { filter.scope = .archived }
            if question.scope == "private" {
                filter.scope = .locked
                filter.privateUnlocked = true
            }
            var plan = QueryPlan()
            plan.site = question.site
            plan.tags = question.tag.map { [$0] } ?? []
            plan.sinceHours = question.sinceHours
            plan.keywords = question.keyword.map { [$0] } ?? []
            plan.visualConcept = question.visualConcept ?? ""
            let actual = plan.apply(to: library.items.filter(filter.contains), now: now).count
            #expect(actual == question.expectedCount, "\(question.id): expected \(question.expectedCount), got \(actual)")
        }
    }
}
