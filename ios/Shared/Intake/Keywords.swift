import Foundation
import FoundationModels

@Generable
struct ItemKeywords {
    @Guide(description: "Short search keywords in both Simplified Chinese and English: topics, objects, places, kinds of people, and what kind of post it is.", .count(4...12))
    var keywords: [String]
}

enum KeywordWriter {
    static var isAvailable: Bool { SystemLanguageModel.default.availability == .available }

    private static let instructions = """
        You write search keywords for a link or image someone saved, so they can find it again later. \
        Use only what the title, text and image labels support. Never invent names or facts.
        """

    /// Nil on unavailability or failure; an empty array is a successful empty result.
    static func keywords(site: String, title: String, text: String?, labels: [String]) async -> [String]? {
        guard isAvailable else { return nil }
        var prompt = ""
        if !site.isEmpty { prompt += "Site: \(site)\n" }
        if !title.isEmpty { prompt += "Title: \(title)\n" }
        if !labels.isEmpty { prompt += "Image labels: \(labels.joined(separator: ", "))\n" }
        if let text, !text.isEmpty { prompt += "Text in the image:\n\(text.prefix(1000))\n" }
        guard !prompt.isEmpty else { return [] }
        return await generateKeywords(prompt: prompt) { prompt in
            let session = LanguageModelSession(instructions: instructions)
            return try await session.respond(to: prompt, generating: ItemKeywords.self).content.keywords
        }
    }

    static func generateKeywords(prompt: String, using generate: (String) async throws -> [String]) async -> [String]? {
        guard let result = try? await generate(prompt), !Task.isCancelled else { return nil }
        let words = result.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var seen = Set<String>()
        return words.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}
