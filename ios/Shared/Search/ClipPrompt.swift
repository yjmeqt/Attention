#if os(iOS)
import Foundation
import FoundationModels
import NaturalLanguage
import Translation

/// Turns a search query into an English CLIP prompt.
/// Prefers Foundation Models; falls back to on-device Translation when the query isn't English.
enum ClipPrompt {
    static func english(for query: String) async -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if SystemLanguageModel.default.availability == .available {
            let session = LanguageModelSession(instructions: """
                Rewrite the user's search into one short English phrase for an image-text model, \
                like "a photo of a young woman" or "a plate of noodles". Keep only the visual idea. \
                Reply with the phrase alone, no quotes.
                """)
            if let response = try? await session.respond(to: trimmed) {
                let phrase = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !phrase.isEmpty { return phrase }
            }
        }

        if looksMostlyLatin(trimmed) { return trimmed }
        if let translated = await translateToEnglish(trimmed) {
            let clean = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { return clean }
        }
        return trimmed
    }

    /// True when the string is already usable as a CLIP text query without translation.
    static func looksMostlyLatin(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty else { return true }
        let latin = letters.filter { $0.isASCII && $0.isLetter }
        return Double(latin.count) / Double(letters.count) >= 0.8
    }

    /// Uses Translation only when the language pair is already installed — never prompts for a download mid-search.
    private static func translateToEnglish(_ text: String) async -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage, dominant != .english else { return nil }
        let source = Locale.Language(identifier: dominant.rawValue)
        let target = Locale.Language(identifier: "en")
        let status = await LanguageAvailability().status(from: source, to: target)
        guard status == .installed else { return nil }
        do {
            let session = try TranslationSession(installedSource: source, target: target)
            return try await session.translate(text).targetText
        } catch {
            return nil
        }
    }
}
#endif
