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

@Suite("Search index invalidation")
struct SearchIndexInvalidationTests {
    @Test func syncedCoverCannotReuseOldVector() async throws {
        let library = Library(directory: URL.temporaryDirectory.appending(path: UUID().uuidString), inMemory: true)
        let item = library.save(.link(URL(string: "https://example.com")!, image: nil))
        item.coverData = Data([1])
        await library.embedPending { _ in Array(repeating: 0.25, count: 512) }
        item.coverData = Data([2]) // CloudKit updates model fields without calling setCover.
        #expect(library.embedding(of: item) == nil)
        await library.embedPending { _ in Array(repeating: 0.5, count: 512) }
        #expect(library.embedding(of: item)?.first == 0.5)
    }

    @Test func changedImageDuringEmbeddingDiscardsResult() async {
        let library = Library(directory: URL.temporaryDirectory.appending(path: UUID().uuidString), inMemory: true)
        let item = library.save(.link(URL(string: "https://example.com")!, image: nil))
        item.coverData = Data([1])
        await library.embedPending { _ in
            item.coverData = Data([2])
            return Array(repeating: 0.25, count: 512)
        }
        #expect(library.embedding(of: item) == nil)
    }

    @Test func coverEditClearsOldSemanticLabelsImmediately() {
        let library = Library(directory: URL.temporaryDirectory.appending(path: UUID().uuidString), inMemory: true)
        let item = library.save(.link(URL(string: "https://example.com")!, image: Data([1])))
        item.visualLabels = ["cat"]
        item.keywords = ["cat"]
        library.setCover(.shared, for: item)
        #expect(!item.matches(search: "cat"))
    }

    @Test func transientLibraryDoesNotConsumeLegacyHistory() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = directory.appending(path: "index.json")
        try Data("[]".utf8).write(to: index)
        let library = Library(directory: directory.appending(path: "demo"), inMemory: true)
        HistoryImport.run(into: library, from: directory)
        #expect(FileManager.default.fileExists(atPath: index.path))
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "index.imported.json").path))
    }
}
