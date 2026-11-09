import Foundation
import Testing
@testable import Attention

@Suite("Analysis failures and retries")
struct AnalysisRetryTests {
    @Test func failedGenerationIsNotAnEmptySuccess() async {
        enum Failure: Error { case unavailable }
        let result = await KeywordWriter.generateKeywords(prompt: "a saved link") { _ in throw Failure.unavailable }
        #expect(result == nil)
        let empty = await KeywordWriter.generateKeywords(prompt: "a saved link") { _ in [] }
        #expect(empty == [])
    }

    @Test func keywordFailureIsRetriedWithABound() async {
        let library = Library(directory: .temporaryDirectory.appending(path: UUID().uuidString), inMemory: true)
        let item = library.save(.link(URL(string: "https://example.com")!, image: nil))
        var attempts = 0
        for _ in 0..<8 {
            await library.analyzePending(target: Library.Analysis.keywords) { _, _, _, _ in
                attempts += 1
                return nil
            }
        }
        #expect(attempts == 3)
        #expect(item.analysisVersion == Library.Analysis.labels)
    }

    @Test func successfulRetryCompletesAnalysis() async {
        let library = Library(directory: .temporaryDirectory.appending(path: UUID().uuidString), inMemory: true)
        let item = library.save(.link(URL(string: "https://example.com")!, image: nil))
        await library.analyzePending(target: Library.Analysis.keywords) { _, _, _, _ in nil }
        await library.analyzePending(target: Library.Analysis.keywords) { _, _, _, _ in ["space"] }
        #expect(item.analysisVersion == Library.Analysis.keywords)
        #expect(item.keywords == ["space"])
    }

    @Test func changedContentDuringAnalysisCannotReceiveOldKeywords() async {
        let library = Library(directory: .temporaryDirectory.appending(path: UUID().uuidString), inMemory: true)
        let item = library.save(.link(URL(string: "https://example.com")!, image: nil))
        item.title = "old"
        await library.analyze(item) { _, _, _, _ in
            item.title = "new"
            return ["old"]
        }
        #expect(item.keywords.isEmpty)
        #expect(item.analysisVersion == 0)
    }
}
