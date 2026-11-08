import Foundation
import FoundationModels
import Testing
@testable import Attention

@MainActor
@Suite("QueryPlan")
struct QueryPlanTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    func makeLibrary() -> Library { Library(directory: directory, inMemory: true) }

    @Test func filtersByTimeSiteTagsAndKeywords() {
        let library = makeLibrary()
        let recent = library.save(.link(URL(string: "https://www.xiaohongshu.com/a")!, image: nil))
        let old = library.save(.link(URL(string: "https://www.xiaohongshu.com/b")!, image: nil))
        let other = library.save(.link(URL(string: "https://youtube.com/c")!, image: nil))
        recent.title = "周末穿搭"
        old.title = "上周穿搭"
        other.title = "穿搭教程"
        old.createdAt = .now.addingTimeInterval(-48 * 3600)
        library.addTag("fashion", to: [recent, old])
        library.save()

        var plan = QueryPlan()
        plan.intent = .count
        plan.sinceHours = 12
        plan.site = "xiaohongshu.com"
        plan.tags = ["fashion"]
        plan.keywords = ["穿搭"]

        let found = plan.apply(to: library.items)
        #expect(found.map(\.id) == [recent.id])
        #expect(plan.summaryChips.contains("xiaohongshu.com"))
        #expect(plan.summaryChips.contains("12h"))
    }

    @Test func visualConceptUsesScoresOrLabels() {
        let library = makeLibrary()
        let a = library.save(.link(URL(string: "https://example.com/a")!, image: nil))
        let b = library.save(.link(URL(string: "https://example.com/b")!, image: nil))
        b.visualLabels = [ImageAnalysis.portrait]
        var plan = QueryPlan()
        plan.visualConcept = "portrait"
        let byLabel = plan.apply(to: library.items)
        #expect(byLabel.map(\.id) == [b.id])
        let byScore = plan.apply(to: library.items, visualScores: [a.id: 0.5], visualThreshold: 0.22)
        #expect(Set(byScore.map(\.id)) == Set([a.id, b.id]))
    }

    @Test func siteDoesNotMatchAnotherDomainContainingIt() {
        let library = makeLibrary()
        let exact = library.save(.link(URL(string: "https://example.com/a")!, image: nil))
        _ = library.save(.link(URL(string: "https://notexample.com/b")!, image: nil))

        var plan = QueryPlan()
        plan.site = "example.com"

        #expect(plan.apply(to: library.items).map(\.id) == [exact.id])
    }

    @Test func tagDoesNotMatchAnotherTagContainingIt() {
        let library = makeLibrary()
        let exact = library.save(.link(URL(string: "https://example.com/a")!, image: nil))
        let other = library.save(.link(URL(string: "https://example.com/b")!, image: nil))
        library.addTag("art", to: [exact])
        library.addTag("cart", to: [other])

        var plan = QueryPlan()
        plan.tags = ["art"]

        #expect(plan.apply(to: library.items).map(\.id) == [exact.id])
    }

    @Test func unsupportedDeviceIsSilentAndRecoverableStatesExplainWhy() {
        #expect(Assistant.message(for: .unavailable(.deviceNotEligible)) == nil)
        #expect(Assistant.message(for: .available) == nil)
        let disabled = Assistant.message(for: .unavailable(.appleIntelligenceNotEnabled))
        let preparing = Assistant.message(for: .unavailable(.modelNotReady))
        #expect(disabled != nil)
        #expect(preparing != nil)
        #expect(disabled != preparing)
    }

    @Test func modelStartupFailureDisablesAsk() {
        let assistant = Assistant()
        #if targetEnvironment(simulator)
        #expect(!assistant.canAsk)
        #endif
        assistant.recordFailure(NSError(domain: "FoundationModels.LanguageModelError", code: -1))
        #expect(assistant.modelFailed)
        #expect(assistant.hasFailure)
        #expect(!assistant.canAsk)
        #expect(!assistant.showsAskEntry)
        assistant.reset()
        #expect(!assistant.canAsk)
        #expect(!assistant.showsAskEntry)
        #expect(assistant.availabilityMessage != nil)
    }
}
