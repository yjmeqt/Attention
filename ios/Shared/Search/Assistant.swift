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

    private let request = SearchRequest()
    private var task: Task<Void, Never>?

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
    var showsAskEntry: Bool { !modelFailed && Self.isAvailable }
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
        let availability = SystemLanguageModel.default.availability
        if availability == .unavailable(.deviceNotEligible) { return nil }
        if let modelFailureMessage { return modelFailureMessage }
        guard availability == .available else { return Self.message(for: availability) }
        #if targetEnvironment(simulator)
        if !modelVerified { return "Checking Apple Intelligence…" }
        #endif
        return nil
    }

    static func message(for availability: SystemLanguageModel.Availability) -> String? {
        switch availability {
        case .available, .unavailable(.deviceNotEligible):
            return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return String(localized: "Turn on Apple Intelligence in Settings to use Ask.")
        case .unavailable(.modelNotReady):
            return String(localized: "Apple Intelligence's model isn't ready yet. It may still be downloading. Please try again later.")
        case .unavailable:
            return String(localized: "Apple Intelligence is temporarily unavailable. Please try again later.")
        }
    }

    var isBusy: Bool { phase == .planning || phase == .matching || phase == .answering }

    func reset() {
        task?.cancel()
        task = nil
        request.cancel()
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

    func isCurrent(in library: Library, scope: FeedFilter) -> Bool {
        request.isCurrent(in: library, filter: scope)
    }

    /// Start synchronously so rapid taps cannot queue competing requests before reset runs.
    func start(_ question: String, in library: Library, scope: FeedFilter) {
        reset()
        guard canAsk else {
            phase = .unavailable
            return
        }
        let token = request.begin(in: library, filter: scope)
        phase = .planning
        task = Task { await run(question, in: library, scope: scope, token: token) }
    }

    private func run(_ question: String, in library: Library, scope: FeedFilter, token: UUID) async {
        guard request.accepts(token, in: library, filter: scope) else { return }
        phase = .planning
        let scopedItems = library.items.filter(scope.contains)
        let sites = Set(scopedItems.map(\.domain).filter { !$0.isEmpty }).sorted().prefix(40)
        let tags = FeedFilter.ranked(scopedItems.flatMap(\.tags)).prefix(40)
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
                guard request.accepts(token, in: library, filter: scope) else { return }
                plan = Self.materialize(snapshot.content)
            }
            guard request.accepts(token, in: library, filter: scope) else { return }
            guard let final = plan else {
                phase = .failed(String(localized: "Couldn't understand that."))
                return
            }
            phase = .matching

            var visualScores: [UUID: Float] = [:]
            let concept = final.visualConcept.trimmingCharacters(in: .whitespaces)
            if !concept.isEmpty, ClipModel.shared.isReady {
                if let text = await ClipModel.shared.textEmbedding(concept) {
                    guard request.accepts(token, in: library, filter: scope) else { return }
                    for item in library.items {
                        guard let image = library.embedding(of: item) else { continue }
                        visualScores[item.id] = ClipModel.cosine(text, image)
                    }
                }
            }

            guard request.accepts(token, in: library, filter: scope) else { return }
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
                guard request.accepts(token, in: library, filter: scope) else { return }
                answer = partial.content
            }
            guard request.accepts(token, in: library, filter: scope) else { return }
            phase = .done
        } catch {
            guard request.accepts(token, in: library, filter: scope) else { return }
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
