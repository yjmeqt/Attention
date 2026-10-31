import Testing
import UIKit
import CoreImage.CIFilterBuiltins
@testable import Attention

@MainActor
@Suite("Library")
struct LibraryTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    func makeLibrary() -> Library { Library(directory: directory, inMemory: true) }

    @Test(arguments: [
        ("https://www.youtube.com/watch?v=1", "youtube.com"),
        ("https://youtu.be/1", "youtube.com"),
        ("https://m.bilibili.com/video/BV1", "bilibili.com"),
        ("https://b23.tv/x", "bilibili.com"),
        ("http://xhslink.com/a/b", "xiaohongshu.com"),
        ("https://twitter.com/jack", "x.com"),
        ("https://music.apple.com/us/x", "music.apple.com"),
    ])
    func domains(url: String, domain: String) {
        #expect(DomainTag.domain(of: URL(string: url)!) == domain)
    }

    @Test func sameLinkUpdatesExistingItem() {
        let library = makeLibrary()
        let first = library.save(.link(URL(string: "https://example.com/a?utm_source=x")!, image: nil))
        library.addTag("read later", to: [first])
        let second = library.save(.link(URL(string: "https://example.com/a")!, image: nil))
        #expect(first.id == second.id)
        #expect(library.items.count == 1)
        #expect(second.tags == ["read later"])
    }

    func jpeg(_ width: CGFloat, _ height: CGFloat, _ color: UIColor) throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try #require(image.jpegData(compressionQuality: 0.9))
    }

    @Test func linkCanShowPreviewSharedOrCustomImage() throws {
        let library = makeLibrary()
        let url = URL(string: "https://example.com/post")!
        let shared = try jpeg(400, 300, .red)
        let preview = try jpeg(300, 400, .blue)
        let item = library.save(.link(url, image: shared))
        library.setMeta(LinkMeta(url: url, site: "Example", title: "Post", imageData: preview), for: item)

        #expect(library.cover(of: item) == .preview)
        #expect(library.previewData(item) == preview)
        #expect(library.meta(for: item)?.imageData == preview)
        #expect(abs(item.thumbnailAspect - 0.75) < 0.01)

        library.setCover(.shared, for: item)
        #expect(library.meta(for: item)?.imageData == shared)
        #expect(abs(item.thumbnailAspect - 4.0 / 3) < 0.01)

        #expect(library.setCustomImage(try jpeg(500, 500, .green), for: item))
        #expect(library.cover(of: item) == .custom)
        #expect(!item.usesSharedImage)
        #expect(abs(item.thumbnailAspect - 1) < 0.01)

        library.removeCustomImage(item)
        #expect(library.data(.custom, of: item) == nil)
        #expect(library.cover(of: item) == .preview)
        #expect(library.data(.source, of: item) == shared)
    }

    @Test func plainLinkCanTakeACustomImage() throws {
        let library = makeLibrary()
        let item = library.save(.link(URL(string: "https://example.com/plain")!, image: nil))
        #expect(library.coverData(item) == nil)
        #expect(!library.setCustomImage(Data("not an image".utf8), for: item))
        #expect(library.setCustomImage(try jpeg(600, 400, .orange), for: item))
        #expect(library.coverData(item) != nil)
        #expect(abs(item.thumbnailAspect - 1.5) < 0.01)
    }

    @Test func sameImageIsSavedOnce() {
        let library = makeLibrary()
        let data = Data(repeating: 7, count: 64)
        let a = library.save(.image(data))
        let b = library.save(.image(data))
        #expect(a.id == b.id)
        #expect(a.isImage)
        #expect(a.domain == DomainTag.images)
    }

    /// What two devices that saved the same link before syncing end up with.
    @Test func duplicatesFromSyncMergeIntoOneItem() {
        let library = makeLibrary()
        let a = library.save(.link(URL(string: "https://example.com/a")!, image: nil))
        let b = library.save(.link(URL(string: "https://example.com/b")!, image: nil))
        library.addTag("music", to: [a])
        library.addTag("later", to: [b])
        library.setPrivate(true, [b])
        library.write(Data([1, 2, 3]), .icon, of: b)
        b.key = a.key
        library.save()

        library.mergeDuplicates()

        #expect(library.items.count == 1)
        let kept = library.items[0]
        // Every device keeps the copy with the lowest id, so they all keep the same one.
        let lowest = a.id.uuidString < b.id.uuidString ? a.id : b.id
        #expect(kept.id == lowest)
        #expect(Set(kept.tags) == ["music", "later"])
        #expect(kept.isPrivate)
        #expect(library.data(.icon, of: kept) == Data([1, 2, 3]))
    }

    @Test func capRemovesOldestNonPrivate() {
        let library = makeLibrary()
        library.maxItems = 3
        let oldest = library.save(.link(URL(string: "https://a.com")!, image: nil))
        library.setPrivate(true, [oldest])
        let second = library.save(.link(URL(string: "https://b.com")!, image: nil))
        library.save(.link(URL(string: "https://c.com")!, image: nil))
        library.save(.link(URL(string: "https://d.com")!, image: nil))
        let keys = Set(library.items.map(\.key))
        #expect(library.items.count == 3)
        #expect(keys.contains(oldest.key))
        #expect(!keys.contains("https://b.com"))
        _ = second
    }

    @Test func capRemovesArchivedFirst() {
        let library = makeLibrary()
        library.maxItems = 3
        let a = library.save(.link(URL(string: "https://a.com")!, image: nil))
        let b = library.save(.link(URL(string: "https://b.com")!, image: nil))
        library.setArchived(true, [b])
        library.save(.link(URL(string: "https://c.com")!, image: nil))
        library.save(.link(URL(string: "https://d.com")!, image: nil))
        let keys = Set(library.items.map(\.key))
        #expect(keys.contains(a.key))
        #expect(!keys.contains("https://b.com"))
    }

    @Test func archivedShowsArchivedItemsAndPrivateShowsAllPrivateOnes() {
        let library = makeLibrary()
        let live = library.save(.link(URL(string: "https://a.com")!, image: nil))
        let archived = library.save(.link(URL(string: "https://b.com")!, image: nil))
        let privateArchived = library.save(.link(URL(string: "https://c.com")!, image: nil))
        library.setArchived(true, [archived, privateArchived])
        library.setPrivate(true, [privateArchived])

        let filter = FeedFilter()
        #expect(filter.apply(library.items).map(\.id) == [live.id])
        filter.scope = .archived
        #expect(filter.apply(library.items).map(\.id) == [archived.id])
        filter.scope = .locked
        filter.privateUnlocked = true
        #expect(filter.apply(library.items).map(\.id) == [privateArchived.id])
    }

    @Test func privateItemsOnlyShowInPrivate() {
        let library = makeLibrary()
        let open = library.save(.link(URL(string: "https://a.com")!, image: nil))
        let hidden = library.save(.link(URL(string: "https://b.com")!, image: nil))
        library.setPrivate(true, [hidden])
        library.addTag("x", to: [open, hidden])

        let filter = FeedFilter()
        #expect(filter.apply(library.items).map(\.id) == [open.id])
        filter.scope = .tag("x")
        #expect(filter.apply(library.items).map(\.id) == [open.id])
        filter.scope = .locked
        #expect(filter.apply(library.items).isEmpty)
        filter.privateUnlocked = true
        #expect(filter.apply(library.items).map(\.id) == [hidden.id])
    }

    @Test func sitesAndTagsNarrowLiveItemsAndSearchNarrowsThem() {
        let library = makeLibrary()
        let a = library.save(.link(URL(string: "https://youtu.be/1")!, image: nil))
        let b = library.save(.link(URL(string: "https://www.youtube.com/watch?v=2")!, image: nil))
        let c = library.save(.link(URL(string: "https://bilibili.com/video/3")!, image: nil))
        a.title = "Swift talk"
        library.addTag("dev", to: [a, c])
        let filter = FeedFilter()
        filter.scope = .site("youtube.com")
        #expect(Set(filter.apply(library.items).map(\.id)) == [a.id, b.id])
        filter.scope = .tag("dev")
        #expect(Set(filter.apply(library.items).map(\.id)) == [a.id, c.id])
        filter.search = "swift"
        #expect(filter.apply(library.items).map(\.id) == [a.id])
        library.setArchived(true, [a])
        #expect(filter.apply(library.items).isEmpty)
    }

    @Test func importsOldHistory() throws {
        let history = directory.appending(path: "History")
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        let id = UUID()
        let json = """
        [{"id":"\(id.uuidString)","date":0,"meta":{"url":"https://example.com/post","site":"example.com","title":"Hello"}}]
        """
        try Data(json.utf8).write(to: history.appending(path: "index.json"))
        let library = makeLibrary()
        HistoryImport.run(into: library, from: history)
        #expect(library.items.count == 1)
        #expect(library.items.first?.title == "Hello")
        #expect(FileManager.default.fileExists(atPath: history.appending(path: "index.imported.json").path))
        HistoryImport.run(into: library, from: history)
        #expect(library.items.count == 1)
    }

    @Test func ocrTitlePicksBigTextNearTheTop() {
        let lines = [
            TextReader.Line(text: "小红书", height: 0.05, top: 0.02),
            TextReader.Line(text: "周末去哪儿", height: 0.06, top: 0.15),
            TextReader.Line(text: "杭州三日游攻略", height: 0.06, top: 0.22),
            TextReader.Line(text: "@旅行的猫", height: 0.03, top: 0.3),
            TextReader.Line(text: "正文很长很长", height: 0.02, top: 0.4),
            TextReader.Line(text: "扫码查看笔记", height: 0.03, top: 0.9),
        ]
        #expect(TextReader.title(from: lines) == "周末去哪儿杭州三日游攻略")
    }

    @Test func readsLinkFromQRCodeImage() async throws {
        let data = try #require(Self.qrImage("https://www.xiaohongshu.com/discovery/item/abc"))
        let capture = await Intake.capture(image: data, link: nil)
        guard case let .link(url, image) = capture else {
            Issue.record("expected a link, got \(String(describing: capture))")
            return
        }
        #expect(url.host() == "www.xiaohongshu.com")
        #expect(image != nil)
    }

    @Test func imageWithoutQRCodeBecomesImageItem() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300))
        let data = renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        }
        guard case .image = await Intake.capture(image: data, link: nil) else {
            Issue.record("expected an image capture")
            return
        }
    }

    @Test func unwrapsProxiedImageURLs() {
        let proxied = "https://ci.xiaohongshu.com/http://sns-webpic-qc.xhscdn.com/a/b!h5_1080jpg?imageMogr2/crop/450x300"
        #expect(Unfurler.imageCandidates(proxied).map(\.absoluteString) == [
            "https://sns-webpic-qc.xhscdn.com/a/b!h5_1080jpg",
            "https://sns-webpic-qc.xhscdn.com/a/b!h5_1080jpg?imageMogr2/crop/450x300",
            proxied,
        ])
        #expect(Unfurler.imageCandidates("http://example.com/a.jpg").map(\.absoluteString) == ["https://example.com/a.jpg"])
        #expect(Unfurler.imageCandidates("https://example.com/a.jpg?w=1").map(\.absoluteString) == ["https://example.com/a.jpg?w=1"])
    }

    @Test func removesSiteSuffixFromTitles() {
        #expect(OpenGraph.removingSiteSuffix("小红书", from: "原来苹果 CEO 也是法拉利车迷？ - 小红书") == "原来苹果 CEO 也是法拉利车迷？")
        #expect(OpenGraph.removingSiteSuffix("GitHub", from: "Pull requests | GitHub") == "Pull requests")
        #expect(OpenGraph.removingSiteSuffix("小红书", from: "小红书") == "小红书")
        #expect(OpenGraph.removingSiteSuffix("小红书", from: "红书日记") == "红书日记")
    }

    @Test func upgradesHTTPLinks() {
        #expect(URL(string: "http://xhslink.com/o/3M8gnOFZeo1")!.upgradedToHTTPS.absoluteString == "https://xhslink.com/o/3M8gnOFZeo1")
        #expect(URL(string: "https://example.com/a?b=1")!.upgradedToHTTPS.absoluteString == "https://example.com/a?b=1")
    }

    @Test func savesHTTPLinksAsHTTPS() {
        let library = Library(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), inMemory: true)
        let item = library.save(.link(URL(string: "http://xhslink.com/o/3M8gnOFZeo1")!, image: nil))
        #expect(item.urlString == "https://xhslink.com/o/3M8gnOFZeo1")
    }

    static func qrImage(_ text: String) -> Data? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let padded = output.composited(over: CIImage(color: .white).cropped(to: output.extent.insetBy(dx: -40, dy: -40)))
        guard let cgImage = CIContext().createCGImage(padded, from: padded.extent) else { return nil }
        return UIImage(cgImage: cgImage).pngData()
    }
}
