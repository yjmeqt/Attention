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
    /// A model startup failure makes availability's optimistic result untrustworthy for this session.
    private(set) var modelFailed = false
    private(set) var modelFailureMessage: String?
    #if targetEnvironment(simulator)
    private(set) var modelVerified = false
    private var checkingModel = false
    #endif

    static var isAvailable: Bool { SystemLanguageModel.default.availability == .available }
    var canAsk: Bool {
        #if targetEnvironment(simulator)
        return modelVerified && !modelFailed && Self.isAvailable
        #else
        return !modelFailed && Self.isAvailable
        #endif
    }
    var hasFailure: Bool {
        if case .failed = phase { return true }
        return false
    }

    var availabilityMessage: String? {
        if let modelFailureMessage { return modelFailureMessage }
        guard Self.isAvailable else { return "Apple Intelligence isn't available on this device." }
        #if targetEnvironment(simulator)
        if !modelVerified { return "Checking Apple Intelligence…" }
        #endif
        return nil
    }

    var isBusy: Bool { phase == .planning || phase == .matching || phase == .answering }

    func reset() {
        phase = .idle
        plan = nil
        matches = []
        answer = ""
        count = 0
    }

    #if targetEnvironment(simulator)
    /// Simulator availability can be optimistic when its model assets don't match the host OS.
    /// Make a real request once before offering Ask.
    func verifyModelIfNeeded() async {
        guard !modelVerified, !modelFailed, !checkingModel, Self.isAvailable else { return }
        checkingModel = true
        defer { checkingModel = false }
        do {
            let session = LanguageModelSession()
            _ = try await session.respond(to: "Reply with OK.")
            modelVerified = true
        } catch {
            recordFailure(error)
        }
    }
    #endif

    func ask(_ question: String, in library: Library, scope: FeedFilter) async {
        guard canAsk else {
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
            recordFailure(error)
        }
    }

    func recordFailure(_ error: Error) {
        let nsError = error as NSError
        #if targetEnvironment(simulator)
        if nsError.code == -1 && nsError.domain.contains("FoundationModels") {
            modelFailed = true
            let message = "Apple Intelligence couldn't start in this simulator (Foundation Models error -1). Check the macOS, Xcode, and simulator versions."
            modelFailureMessage = message
            phase = .failed(message)
            return
        }
        #endif
        phase = .failed(error.localizedDescription)
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
