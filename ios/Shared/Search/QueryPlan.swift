import Foundation
import FoundationModels

@Generable
enum QueryIntent: String, Equatable {
    case count, list, find
}

/// Structured search the on-device model fills in; code runs it.
@Generable
struct QueryPlan: Equatable {
    var intent: QueryIntent = .list
    @Guide(description: "Hours back from now to include. Nil means no time limit.", .range(1...720))
    var sinceHours: Int?
    @Guide(description: "Exact domain like xiaohongshu.com or youtube.com, or nil.")
    var site: String?
    @Guide(description: "User tags that must all be present.")
    var tags: [String] = []
    @Guide(description: "Words that must appear in title, OCR, keywords or labels.")
    var keywords: [String] = []
    @Guide(description: "English visual concept for image matching, e.g. a photo of a young woman. Empty if none.")
    var visualConcept: String = ""

    /// Deterministic filter. Numbers come from here, never from the model.
    @MainActor
    func apply(to items: [LibraryItem], now: Date = .now, visualScores: [UUID: Float] = [:], visualThreshold: Float = 0.22) -> [LibraryItem] {
        items.filter { item in
            if let hours = sinceHours {
                guard item.createdAt >= now.addingTimeInterval(Double(-hours) * 3600) else { return false }
            }
            if let site, !site.isEmpty {
                guard item.domain.caseInsensitiveCompare(site) == .orderedSame else { return false }
            }
            for tag in tags where !item.tags.contains(where: { $0.caseInsensitiveCompare(Library.normalizedTag(tag)) == .orderedSame }) {
                return false
            }
            for word in keywords where !item.matches(search: word) {
                return false
            }
            if !visualConcept.trimmingCharacters(in: .whitespaces).isEmpty {
                let score = visualScores[item.id] ?? 0
                let labeled = item.visualLabels.contains { visualConcept.localizedStandardContains($0) }
                    || item.keywords.contains { $0.localizedStandardContains(visualConcept) || visualConcept.localizedStandardContains($0) }
                    || item.matches(search: visualConcept)
                guard score >= visualThreshold || labeled else { return false }
            }
            return true
        }
    }

    var summaryChips: [String] {
        var chips: [String] = []
        if let site, !site.isEmpty { chips.append(site) }
        if let hours = sinceHours { chips.append(hours < 48 ? "\(hours)h" : "\(hours / 24)d") }
        chips.append(contentsOf: tags.map { "#\($0)" })
        chips.append(contentsOf: keywords)
        let visual = visualConcept.trimmingCharacters(in: .whitespaces)
        if !visual.isEmpty { chips.append(visual) }
        return chips
    }
}
