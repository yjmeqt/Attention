#if os(iOS)
import Foundation

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
