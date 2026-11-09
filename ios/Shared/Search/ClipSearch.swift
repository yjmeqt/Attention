#if os(iOS)
import Foundation
import CryptoKit

extension Library {
    /// Float16 bytes of a 512-d L2-normalized embedding, or nil when missing.
    func embedding(of item: LibraryItem) -> [Float]? {
        guard let data = data(.embedding, of: item), data.count == 32 + ClipModel.embeddingDimensions * 2,
              let image = searchImage(item), data.prefix(32) == Data(SHA256.hash(data: image)) else { return nil }
        return Data(data.dropFirst(32)).withUnsafeBytes { raw in
            let halfs = raw.bindMemory(to: Float16.self)
            return halfs.map { Float($0) }
        }
    }

    func writeEmbedding(_ values: [Float]?, of item: LibraryItem) {
        guard let image = searchImage(item), let values, values.count == ClipModel.embeddingDimensions else {
            write(nil, .embedding, of: item)
            return
        }
        let halfs = values.map { Float16($0) }
        let bytes = Data(SHA256.hash(data: image)) + halfs.withUnsafeBytes { Data($0) }
        write(bytes, .embedding, of: item)
    }

    /// Embeds items that still need a vector, when MobileCLIP is ready.
    func embedPending() async {
        guard ClipModel.shared.isReady else { return }
        await embedPending { await ClipModel.shared.imageEmbedding(data: $0) }
    }

    /// The injected embedder lets tests verify the queue without downloading the model.
    func embedPending(using embed: (Data) async -> [Float]?) async {
        let pending = items.filter { embedding(of: $0) == nil }
        for item in pending {
            if Task.isCancelled { return }
            guard contains(item) else { continue }
            let image = searchImage(item)
            guard let image, let values = await embed(image) else { continue }
            guard !Task.isCancelled, contains(item), searchImage(item) == image else { continue }
            writeEmbedding(values, of: item)
        }
    }
}
#endif
