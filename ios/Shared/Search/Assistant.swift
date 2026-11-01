#if os(iOS) && !SHARE_EXTENSION
import Foundation
import FoundationModels
import Observation

/// Turns a natural-language question into a QueryPlan, runs it in code, then streams a one-line answer.
@Observable
@MainActor
final class Assistant {
    enum Phase: Equatable {
        case idle, planning, matching, answering, done, unavailable, failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var plan: QueryPlan?
    private(set) var matches: [LibraryItem] = []
    private(set) var answer = ""
    private(set) var count = 0

    static var isAvailable: Bool { SystemLanguageModel.default.availability == .available }

    /// Looks like a question worth asking, not a plain keyword search.
    static func looksLikeQuestion(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 4 else { return false }
        if t.hasSuffix("?") || t.hasSuffix("？") { return true }
        let lower = t.lowercased()
        for prefix in ["how many", "how much", "what did", "which", "when did", "show me", "find me"] {
            if lower.hasPrefix(prefix) { return true }
        }
        for prefix in ["多少", "几个", "哪些", "什么时候", "帮我找", "找一下", "有没有"] {
            if t.hasPrefix(prefix) { return true }
        }
        return false
    }

    func reset() {
        phase = .idle
        plan = nil
        matches = []
        answer = ""
        count = 0
    }

    func ask(_ question: String, in library: Library, scope: FeedFilter) async {
        guard Self.isAvailable else {
            phase = .unavailable
            return
        }
        reset()
        phase = .planning
        let sites = Set(library.items.map(\.domain).filter { !$0.isEmpty }).sorted().prefix(40)
        let tags = library.allTags.prefix(40)
        let instructions = """
            You turn a question about a personal link-and-image library into a QueryPlan. \
            Use only these domains when setting site: \(sites.joined(separator: ", ")). \
            Known tags: \(tags.joined(separator: ", ")). \
            Prefer site domains over guesses. Put visual ideas (people, food, outfits) in visualConcept as short English. \
            Put literal words to match in keywords. sinceHours is relative to now. Never invent counts.
            """
        let session = LanguageModelSession(instructions: instructions)
        do {
            // Stream the plan so chips appear as fields fill in.
            let stream = session.streamResponse(to: question, generating: QueryPlan.self)
            for try await snapshot in stream {
                plan = Self.materialize(snapshot.content)
            }
            guard let final = plan else {
                phase = .failed(String(localized: "Couldn't understand that."))
                return
            }
            phase = .matching

            var visualScores: [UUID: Float] = [:]
            let concept = final.visualConcept.trimmingCharacters(in: .whitespaces)
            if !concept.isEmpty, ClipModel.shared.isReady {
                if let text = await ClipModel.shared.textEmbedding(concept) {
                    for item in library.items {
                        guard let image = library.embedding(of: item) else { continue }
                        visualScores[item.id] = ClipModel.cosine(text, image)
                    }
                }
            }

            // Scope only (all / site / tag / private) — the typed question is not a text filter.
            let scoped = library.items.filter(scope.contains)
            let found = final.apply(to: scoped, visualScores: visualScores, visualThreshold: ClipModel.matchThreshold)
            matches = found
            count = found.count

            phase = .answering
            let chipText = final.summaryChips.joined(separator: " · ")
            let fact = """
                The library search returned exactly \(count) item(s). \
                Filters: \(chipText.isEmpty ? "none" : chipText). \
                Intent: \(final.intent.rawValue). \
                Write one short sentence answering the user in their language. \
                Use the number \(count) exactly. Do not invent other numbers.
                """
            let reply = session.streamResponse(to: fact)
            for try await partial in reply {
                answer = partial.content
            }
            phase = .done
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private static func materialize(_ partial: QueryPlan.PartiallyGenerated) -> QueryPlan {
        var plan = QueryPlan()
        if let intent = partial.intent { plan.intent = intent }
        plan.sinceHours = partial.sinceHours ?? nil
        plan.site = partial.site ?? nil
        plan.tags = partial.tags ?? []
        plan.keywords = partial.keywords ?? []
        plan.visualConcept = partial.visualConcept ?? ""
        return plan
    }
}
#endif
