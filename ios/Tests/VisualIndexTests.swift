import Foundation
import Testing
@testable import Attention

@Suite("Visual search indexing")
struct VisualIndexTests {
    @Test func indexesEveryPendingPreview() async throws {
        let library = Library(directory: URL.temporaryDirectory.appending(path: UUID().uuidString), inMemory: true)
        for number in 0..<20 {
            let url = try #require(URL(string: "https://example.com/preview/\(number)"))
            let item = library.save(.link(url, image: nil))
            library.write(Data([UInt8(number)]), .cover, of: item)
        }

        await library.embedPending { image in
            Array(repeating: Float(image[0]) / 20, count: ClipModel.embeddingDimensions)
        }

        #expect(library.items.count == 20)
        #expect(library.items.allSatisfy { library.embedding(of: $0) != nil })
        #expect(Set(library.items.compactMap { library.embedding(of: $0)?.first }).count == 20)
    }
}

@Suite("Live OG image indexing", .enabled(if: ProcessInfo.processInfo.environment["ATTENTION_LIVE_NETWORK"] != nil))
struct LiveOGImageTests {
    @Test func realPreviewFlowsIntoSearchIndex() async throws {
        let url = try #require(URL(string: "https://science.nasa.gov/earth/earth-observatory/image-of-the-day/"))
        let meta = try await Unfurler.html(url)
        let ogImage = try #require(meta.imageData)
        let library = Library(directory: URL.temporaryDirectory.appending(path: UUID().uuidString), inMemory: true)
        let item = library.save(.link(url, image: nil))
        library.setMeta(meta, for: item)
        #expect(library.previewData(item) == ogImage)

        await library.analyze(item)
        #expect(item.analysisVersion >= Library.Analysis.labels)
        await library.embedPending { image in
            #expect(image == ogImage)
            return Array(repeating: 0.5, count: ClipModel.embeddingDimensions)
        }
        #expect(library.embedding(of: item) != nil)
    }
}
