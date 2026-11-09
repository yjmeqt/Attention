import Testing
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CoreImage.CIFilterBuiltins
@testable import Attention

@MainActor
@Suite("Library")
struct LibraryTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    func makeLibrary() -> Library { Library(directory: directory, inMemory: true) }

    @Test func defaultShareFormatRespectsPreferenceAndAvailableContent() throws {
        let library = makeLibrary()
        let text = library.save(Capture(text: "Full text **including literal markup**"))
        let link = library.save(Capture(url: URL(string: "https://example.com/article")!))
        let image = library.save(Capture(image: try jpeg(200, 200, .blue)))
        #expect(ShareDefault.link.format(for: text) == .text)
        #expect(ShareDefault.image.format(for: text) == .image)
        #expect(ShareDefault.link.format(for: link) == .link)
        #expect(ShareDefault.image.format(for: link) == .image)
        #expect(ShareDefault.link.format(for: image) == .image)
        #expect(ShareDefault.image.format(for: image) == .image)
        #expect(ShareDefault(rawValue: "link") == .link)
        #expect(ShareDefault(rawValue: "image") == .image)
    }

    @Test func textCardIncludesAppStoreQRCode() throws {
        let image = try #require(TextCardRenderer.render("A small thought."))
        let cgImage = try #require(image.cgImage)
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                             options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let urls = detector.features(in: CIImage(cgImage: cgImage))
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        #expect(urls == [Brand.appStoreURL.absoluteString])
    }

    @Test func textCardCanOmitAppStoreQRCode() throws {
        let image = try #require(TextCardRenderer.render("A small thought.", showsAppStoreQR: false))
        let cgImage = try #require(image.cgImage)
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                             options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        #expect(detector.features(in: CIImage(cgImage: cgImage)).isEmpty)
    }

    @Test func textCardPromotionPreferenceDefaultsOnAndRespectsOptOut() throws {
        let suite = "TextCardPromotionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(TextCardPromotion.isEnabled(in: defaults))
        defaults.set(false, forKey: TextCardPromotion.key)
        #expect(!TextCardPromotion.isEnabled(in: defaults))
        defaults.set(true, forKey: TextCardPromotion.key)
        #expect(TextCardPromotion.isEnabled(in: defaults))
    }

    @Test func shortTextRendersAnAdaptiveCard() throws {
        let library = makeLibrary()
        let item = library.save(Capture(text: "A small thought."))
        let image = try #require(library.fullImage(item))
        #expect(image.cgImage?.width == 1080)
        #expect(image.size.height < 200)
        let paragraphs = library.save(Capture(text: "First paragraph.\n\n第二段 👩🏽‍💻\n\n**Literal markdown**"))
        let taller = try #require(library.fullImage(paragraphs))
        #expect(taller.size.height > image.size.height)
    }

    @Test func longTextCardIsBoundedAndPreservesTheBody() throws {
        let library = makeLibrary()
        let body = String(repeating: "**Literal markdown** 中文 👩🏽‍💻\n\nA paragraph worth keeping.\n", count: 200)
        let item = library.save(Capture(text: body))
        let image = try #require(library.fullImage(item))
        #expect(image.cgImage?.width == 1080)
        #expect(image.size.height <= 720)
        #expect(item.text == body)
        #expect(item.url == nil)
        #expect(library.data(.source, of: item) == nil)
        let longer = library.save(Capture(text: body + body))
        let longerImage = try #require(library.fullImage(longer))
        #expect(longerImage.size == image.size)
        let actions = ItemActions(library: library)
        actions.copyText(item)
        #expect(UIPasteboard.general.string == body)
    }

    @Test func capturesPlainTextWithoutURL() async {
        let capture = await Intake.capture(from: [NSItemProvider(object: "A note without links" as NSString)])
        #expect(capture != nil)
    }

    @Test func proseWithURLIsNotLinkOnly() async {
        let url = URL(string: "https://example.com/article")!
        let capture = await Intake.capture(from: [NSItemProvider(object: "Read this https://example.com/article tomorrow" as NSString)])
        #expect(capture != nil)
        #expect(capture != .link(url, image: nil))
    }


    @Test func preservesBodiesAndSeparatesStandaloneURLs() async throws {
        let body = " \tFirst paragraph\n\nhttps://example.com/a and https://example.org/b\n "
        let capture = try #require(await Intake.capture(from: [NSItemProvider(object: body as NSString)]))
        #expect(capture.text == body)
        #expect(capture.url == nil)
        let standalone = try #require(await Intake.capture(from: [NSItemProvider(object: " \nhttps://example.com/a\t" as NSString)]))
        #expect(standalone.text == nil)
        #expect(standalone.url?.absoluteString == "https://example.com/a")
        #expect(await Intake.capture(from: [NSItemProvider(object: " \n\t" as NSString)]) == nil)
    }

    @Test func explicitURLAndDistinctBodiesCoexist() async throws {
        let url = URL(string: "https://example.org/explicit")!
        let capture = try #require(await Intake.capture(from: [
            NSItemProvider(object: url as NSURL),
            NSItemProvider(object: url.absoluteString as NSString),
            NSItemProvider(object: "First body https://example.com/embedded" as NSString),
            NSItemProvider(object: "Second body" as NSString),
        ]))
        #expect(capture.url == url)
        #expect(capture.text == "First body https://example.com/embedded\n\nSecond body")
    }

    @Test func standaloneSchemelessWebURLRemainsLink() async throws {
        let capture = try #require(await Intake.capture(from: [NSItemProvider(object: " www.example.com/path " as NSString)]))
        #expect(capture.url?.host() == "www.example.com")
        #expect(capture.text == nil)
    }

    @Test func oneProviderCanContainExplicitURLAndBody() async throws {
        let provider = NSItemProvider(object: URL(string: "https://example.com/explicit")! as NSURL)
        provider.registerObject("Actual body" as NSString, visibility: .all)
        let capture = try #require(await Intake.capture(from: [provider]))
        #expect(capture.url?.path == "/explicit")
        #expect(capture.text == "Actual body")
    }

    @Test func repeatedPayloadsKeepTheirOrder() async throws {
        let providers = ["A", "B", "A"].map { NSItemProvider(object: $0 as NSString) }
        let capture = try #require(await Intake.capture(from: providers))
        #expect(capture.text == "A\n\nB\n\nA")
        let items = providers.map { provider in
            let item = NSExtensionItem()
            item.attachments = [provider]
            return item
        }
        #expect(await Intake.capture(from: items)?.text == "A\n\nB\n\nA")
    }

    @Test func multipleURLPayloadsDoNotLoseTheSecondURL() async throws {
        let capture = try #require(await Intake.capture(from: [
            NSItemProvider(object: "https://example.com/a" as NSString),
            NSItemProvider(object: "https://example.org/b" as NSString),
        ]))
        #expect(capture.url == nil)
        #expect(capture.text == "https://example.com/a\n\nhttps://example.org/b")
    }

    @Test func attributedContentFallbackNeverUsesTitleAsBody() async throws {
        let item = NSExtensionItem()
        item.attributedContentText = NSAttributedString(string: "  fallback\nbody  ")
        item.attributedTitle = NSAttributedString(string: "Not the body")
        let capture = try #require(await Intake.capture(from: [item]))
        #expect(capture.text == "  fallback\nbody  ")
        item.attributedContentText = nil
        item.attributedTitle = NSAttributedString(string: "A title mentioning https://example.com")
        #expect(await Intake.capture(from: [item]) == nil)
    }

    @Test func textSurvivesStorageSearchAndEnrichment() async throws {
        let body = " \tUnique needle\n\nSecond paragraph  "
        let library = Library(directory: directory)
        let item = library.save(Capture(text: body))
        #expect(item.hasText && item.isTextOnly && !item.isImage)
        #expect(item.matches(search: "needle"))
        #expect(item.displayTitle == "Unique needle Second paragraph")
        await library.enrich(item, fetchPreview: { url in
            Issue.record("Text-only capture must not fetch")
            return Unfurler.Result(meta: LinkMeta(url: url, site: "", title: ""), isFallback: true)
        }, readText: { _ in
            Issue.record("Text-only capture must not run OCR")
            return nil
        })
        #expect(item.text == body)
        #expect(item.ocrText == nil)
        let reopened = Library(directory: directory)
        #expect(reopened.items.first?.text == body)
    }

    @Test func bodyIdentityIncludesExactTextURLAndImage() throws {
        let library = makeLibrary()
        let url = URL(string: "https://example.com/a")!
        let image = try jpeg(200, 200, .blue)
        let a = library.save(Capture(url: url, text: "Message"))
        #expect(library.save(Capture(url: url, text: "Message")).id == a.id)
        #expect(library.save(Capture(url: url, text: "Message ")).id != a.id)
        #expect(library.save(Capture(text: "Message")).id != a.id)
        #expect(library.save(Capture(url: url, image: image, text: "Message")).id != a.id)
        let imageBody = library.save(Capture(image: image, text: "Caption"))
        #expect(imageBody.isImage && imageBody.hasText && !imageBody.isTextOnly)
        #expect(library.data(.source, of: imageBody) == image)
    }

    @Test func retryPreservesCompositeIdentityAndEnrichmentBody() async {
        let library = makeLibrary()
        let url = URL(string: "http://example.com/a")!
        let a = library.save(Capture(url: url, text: "One"))
        let b = library.save(Capture(url: url, text: "Two"))
        let keys = Set([a.key, b.key])
        a.urlString = url.absoluteString
        b.urlString = url.absoluteString
        await library.retryMissingPreviews { url in
            Unfurler.Result(meta: LinkMeta(url: url, site: "Example", title: "Fetched"), isFallback: false)
        }
        library.mergeDuplicates()
        #expect(library.items.count == 2)
        #expect(Set(library.items.map(\.key)) == keys)
        #expect(Set(library.items.compactMap(\.text)) == ["One", "Two"])
        #expect(library.items.allSatisfy { $0.url?.scheme == "https" })
    }

    @Test func rawRichFormatsDoNotBecomeBody() async {
        for type in [UTType.rtf, .html] {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { done in
                done(Data("<b>https://example.com/not-standalone</b>".utf8), nil)
                return nil
            }
            let capture = await Intake.capture(from: [provider])
            #expect(capture?.text == nil)
            #expect(capture?.url == nil)
        }
    }

    @Test func duplicateMergeRetainsMissingBody() {
        let library = makeLibrary()
        let a = library.save(Capture(text: "Body"))
        let b = library.save(.link(URL(string: "https://example.com")!, image: nil))
        a.id = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        b.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        b.key = a.key
        library.save()
        library.mergeDuplicates()
        #expect(library.items.count == 1)
        #expect(library.items.first?.text == "Body")
    }

    @Test func QRAndImageCaptureKeepTheirBody() async throws {
        let qr = try #require(Self.qrImage("https://example.com/qr"))
        let capture = try #require(await Intake.capture(image: qr, link: nil, text: "Caption"))
        #expect(capture.url?.path == "/qr")
        #expect(capture.image != nil)
        #expect(capture.text == "Caption")
    }

    @Test func previewCompletionIgnoresDeletedItemAndReplacement() async throws {
        let library = makeLibrary()
        let url = URL(string: "https://example.com/pending")!
        let item = library.save(.link(url, image: nil))
        let folder = library.folder(item)
        let preview = try jpeg(400, 300, .blue)
        var replacement: Attention.LibraryItem?
        let notice = await library.enrich(item, fetchPreview: { url in
            library.delete([item])
            replacement = library.save(.link(url, image: nil))
            return Unfurler.Result(meta: LinkMeta(url: url, site: "Example", title: "Late result", imageData: preview), isFallback: false)
        })
        #expect(notice == nil)
        #expect(library.enriching.isEmpty)
        #expect(library.items.count == 1)
        #expect(replacement?.title == "")
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func ocrCompletionIgnoresDeletedImage() async throws {
        let library = makeLibrary()
        let item = library.save(.image(try jpeg(200, 200, .blue)))
        let id = item.id
        let folder = library.folder(item)
        let notice = await library.enrich(item, readText: { _ in
            await MainActor.run { library.delete(library.items.filter { $0.id == id }) }
            return TextReader.Result(title: "Late OCR", fullText: "Late OCR")
        })
        #expect(notice == nil)
        #expect(library.items.isEmpty)
        #expect(library.enriching.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func retrySkipsItemsDeletedWhileEarlierPreviewLoads() async {
        let library = makeLibrary()
        library.save(.link(URL(string: "https://example.com/one")!, image: nil))
        library.save(.link(URL(string: "https://example.com/two")!, image: nil))
        var fetches = 0
        await library.retryMissingPreviews(fetchPreview: { url in
            fetches += 1
            library.delete(library.items)
            return Unfurler.Result(meta: LinkMeta(url: url, site: "Example", title: "Late result"), isFallback: false)
        })
        #expect(fetches == 1)
        #expect(library.items.isEmpty)
        #expect(library.enriching.isEmpty)
    }

    @Test func delayedActionsIgnoreDeletedItem() {
        let library = makeLibrary()
        let item = library.save(.link(URL(string: "https://example.com/deleted")!, image: nil))
        let actions = ItemActions(library: library)
        library.delete([item])
        actions.copyLink(item)
        actions.shareImage(item)
        actions.openInBrowser(item)
        #expect(actions.notice == nil)
        #expect(actions.browser == nil)
    }

    @Test func deletedDetailDoesNotRender() {
        let library = makeLibrary()
        let item = library.save(.link(URL(string: "https://example.com/deleted")!, image: nil))
        library.delete([item])
        let host = UIHostingController(rootView: ItemDetailView(item: item, library: library))
        #expect(host.sizeThatFits(in: CGSize(width: 280, height: 600)).height == 0)
    }

    @Test func collectionTeardownDetachesCallbacks() {
        typealias Feed = FeedCollection<EmptyView, EmptyView>
        let coordinator = Feed.Coordinator()
        let layout = StaggeredLayout()
        layout.height = { _, _ in 100 }
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.delegate = coordinator
        coordinator.layout = layout
        Feed.dismantleUIView(view, coordinator: coordinator)
        #expect(view.delegate == nil)
        #expect(layout.height(0, 280) == 0)
    }

    @Test func deletedLastTileCanFinishRendering() {
        let library = Library(directory: directory)
        let item = library.save(.link(URL(string: "https://example.com/deleted")!, image: nil))
        library.delete([item])
        #expect(library.items.isEmpty)

        // A collection cell or context-menu preview can outlive its deleted model.
        let host = UIHostingController(rootView: FeedTile(item: item, library: library))
        let size = host.sizeThatFits(in: CGSize(width: 280, height: 600))
        #expect(size.height == 0)
    }

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

    @Test func searchMatchesEveryWordAcrossFields() {
        let library = makeLibrary()
        let item = library.save(.link(URL(string: "https://www.xiaohongshu.com/explore/1")!, image: nil))
        item.title = "SwiftUI 布局技巧"
        item.authorName = "旅行的猫"
        item.authorHandle = "catwalks"
        library.addTag("design", to: [item])
        #expect(item.matches(search: "布局 swiftui"))
        #expect(item.matches(search: "  猫  "))
        #expect(item.matches(search: "catwalks design"))
        #expect(item.matches(search: "xiaohongshu 技巧"))
        #expect(!item.matches(search: "swiftui 美食"))
        #expect(item.matches(search: " "))
    }

    @Test func clipPromptTreatsLatinAsAlreadyEnglish() {
        #expect(ClipPrompt.looksMostlyLatin("a photo of noodles"))
        #expect(ClipPrompt.looksMostlyLatin("SwiftUI"))
        #expect(!ClipPrompt.looksMostlyLatin("小红书美女"))
        #expect(!ClipPrompt.looksMostlyLatin("週末穿搭"))
    }

    @Test func visualScoresWidenAndSortSearch() {
        let library = makeLibrary()
        let a = library.save(.link(URL(string: "https://example.com/a")!, image: nil))
        let b = library.save(.link(URL(string: "https://example.com/b")!, image: nil))
        a.title = "noodles"
        b.title = "unrelated"
        let filter = FeedFilter()
        filter.search = "portrait"
        #expect(filter.apply(library.items).isEmpty)
        let scores = [a.id: Float(0.1), b.id: Float(0.4)]
        let found = filter.apply(library.items, visualScores: scores, visualThreshold: 0.22)
        #expect(found.map(\.id) == [b.id])
        filter.search = "noodles"
        let both = filter.apply(library.items, visualScores: [b.id: 0.5], visualThreshold: 0.22)
        #expect(both.map(\.id) == [b.id, a.id])
    }

    @Test func searchFindsKeywordsAndVisualLabels() {
        let library = makeLibrary()
        let item = library.save(.link(URL(string: "https://www.xiaohongshu.com/explore/2")!, image: nil))
        item.keywords = ["穿搭", "outfit"]
        item.visualLabels = ["clothing", ImageAnalysis.portrait]
        #expect(item.matches(search: "穿搭"))
        #expect(item.matches(search: "clothing"))
        #expect(item.matches(search: "人像"))
        #expect(!item.matches(search: "美食"))
    }

    @Test func mergingKeepsTheNewerAnalysis() {
        let library = makeLibrary()
        let a = library.save(.link(URL(string: "https://example.com/a")!, image: nil))
        let b = library.save(.link(URL(string: "https://example.com/b")!, image: nil))
        b.key = a.key
        let (keeper, other) = a.id.uuidString < b.id.uuidString ? (a, b) : (b, a)
        keeper.visualLabels = ["old"]
        keeper.analysisVersion = Library.Analysis.labels
        other.visualLabels = ["food"]
        other.keywords = ["美食"]
        other.analysisVersion = Library.Analysis.keywords
        library.save()
        library.mergeDuplicates()
        #expect(library.items.count == 1)
        #expect(keeper.visualLabels == ["food"])
        #expect(keeper.keywords == ["美食"])
        #expect(keeper.analysisVersion == Library.Analysis.keywords)
    }

    @Test func importsOldHistory() throws {
        let history = directory.appending(path: "History")
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        let id = UUID()
        let json = """
        [{"id":"\(id.uuidString)","date":0,"meta":{"url":"https://example.com/post","site":"example.com","title":"Hello"}}]
        """
        try Data(json.utf8).write(to: history.appending(path: "index.json"))
        let library = Library(directory: directory, inMemory: false)
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
        #expect(capture?.url?.host() == "www.xiaohongshu.com")
        #expect(capture?.image != nil)
    }

    @Test func imageWithoutQRCodeBecomesImageItem() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300))
        let data = renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        }
        let capture = await Intake.capture(image: data, link: nil)
        #expect(capture?.url == nil)
        #expect(capture?.image != nil)
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
