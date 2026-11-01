#if os(iOS)
import Foundation
import FoundationModels

/// Turns a search query into an English CLIP prompt when the on-device model is available.
enum ClipPrompt {
    static func english(for query: String) async -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard SystemLanguageModel.default.availability == .available else { return trimmed }
        let session = LanguageModelSession(instructions: """
            Rewrite the user's search into one short English phrase for an image-text model, \
            like "a photo of a young woman" or "a plate of noodles". Keep only the visual idea. \
            Reply with the phrase alone, no quotes.
            """)
        let response = try? await session.respond(to: trimmed)
        let phrase = response?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
        return phrase.isEmpty ? trimmed : phrase
    }
}

extension Library {
    /// Float16 bytes of a 512-d L2-normalized embedding, or nil when missing.
    func embedding(of item: LibraryItem) -> [Float]? {
        guard let data = data(.embedding, of: item), data.count == ClipModel.embeddingDimensions * 2 else { return nil }
        return data.withUnsafeBytes { raw in
            let halfs = raw.bindMemory(to: Float16.self)
            return halfs.map { Float($0) }
        }
    }

    func writeEmbedding(_ values: [Float]?, of item: LibraryItem) {
        guard let values, values.count == ClipModel.embeddingDimensions else {
            write(nil, .embedding, of: item)
            return
        }
        var halfs = values.map { Float16($0) }
        write(halfs.withUnsafeBytes { Data($0) }, .embedding, of: item)
    }

    /// Embeds items that still need a vector, when MobileCLIP is ready.
    func embedPending() async {
        guard ClipModel.shared.isReady else { return }
        let pending = items.filter { data(.embedding, of: $0) == nil }
        for item in pending.prefix(16) {
            let image = item.isImage ? data(.source, of: item) : coverData(item)
            guard let image, let values = await ClipModel.shared.imageEmbedding(data: image) else { continue }
            writeEmbedding(values, of: item)
        }
    }
}
#endif
