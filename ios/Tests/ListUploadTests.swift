import CryptoKit
import Foundation
import Testing
import UIKit
@testable import Attention

@MainActor
@Suite("Sharing a list")
struct ListUploadTests {
    private func library() -> Library {
        Library(directory: .temporaryDirectory.appending(path: UUID().uuidString), inMemory: true)
    }

    private func photo(_ size: CGSize = CGSize(width: 1600, height: 900)) -> Data {
        UIGraphicsImageRenderer(size: size, format: .init(for: .init(displayScale: 1))).jpegData(withCompressionQuality: 0.9) { context in
            for index in 0..<16 {
                UIColor(hue: Double(index) / 16, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                context.fill(CGRect(x: Double(index) * size.width / 16, y: 0, width: size.width / 16, height: size.height))
            }
        }
    }

    @Test("Shares links and text, newest first; leaves out images, private and archived items")
    func draft() {
        let library = library()
        let old = library.save(Capture(url: URL(string: "https://example.com/old")!))
        let text = library.save(Capture(text: "Remember the milk"))
        let image = library.save(.image(photo()))
        let secret = library.save(Capture(url: URL(string: "https://example.com/secret")!))
        let archived = library.save(Capture(url: URL(string: "https://example.com/archived")!))
        let new = library.save(Capture(url: URL(string: "https://example.com/new?utm_source=x")!))
        let untagged = library.save(Capture(url: URL(string: "https://example.com/other")!))
        library.addTag("Weekend", to: [old, text, image, secret, archived, new])
        library.setPrivate(true, [secret])
        library.setArchived(true, [archived])
        _ = untagged

        let draft = ListDraft(tag: "Weekend", library: library)
        #expect(draft.items.map(\.id) == library.items.filter { [new.id, text.id, old.id].contains($0.id) }.map(\.id))
        #expect(draft.items.first?.id == new.id)
        #expect(draft.skipped == .init(privateItems: 1, images: 1, overLimit: 0))
    }

    @Test("Stops at the server's 100 items")
    func limit() {
        let library = library()
        let items = (0..<103).map { library.save(Capture(url: URL(string: "https://example.com/\($0)")!)) }
        library.addTag("Lots", to: items)
        let draft = ListDraft(tag: "Lots", library: library)
        #expect(draft.items.count == 100)
        #expect(draft.skipped.overLimit == 3)
    }

    @Test("Builds the snapshot the server expects, with small thumbnails for the first 20 items")
    func upload() async throws {
        let library = library()
        let link = library.save(Capture(url: URL(string: "https://example.com/post?utm_source=feed&id=7")!))
        #expect(library.setCustomImage(photo(), for: link))
        link.title = "A post"
        link.authorName = "Someone"
        let text = library.save(Capture(text: String(repeating: "word ", count: 2000)))
        library.addTag("Weekend", to: [link, text])
        let upload = await ListUpload.make(title: "  Weekend reads ", draft: ListDraft(tag: "Weekend", library: library), library: library, lang: "zh-Hans-CN")

        // The assertion signs these bytes before the upload sends them, so they mustn't change in between.
        #expect(upload.json == upload.json)
        let json = try #require(try JSONSerialization.jsonObject(with: upload.json) as? [String: Any])
        #expect(json["v"] as? Int == 1)
        #expect(json["title"] as? String == "Weekend reads")
        #expect(json["lang"] as? String == "zh-Hans-CN")
        let items = try #require(json["items"] as? [[String: Any]])
        #expect(items.count == 2)
        let textItem = try #require(items.first { $0["kind"] as? String == "text" })
        #expect((textItem["text"] as? String)?.count == ListUpload.limits.text)
        let linkItem = try #require(items.first { $0["kind"] as? String == "link" })
        #expect(linkItem["url"] as? String == "https://example.com/post?id=7")
        #expect(linkItem["title"] as? String == "A post")
        #expect(linkItem["author"] as? String == "Someone")
        let part = try #require(linkItem["thumb"] as? String)
        let thumb = try #require(upload.thumbs[part])
        #expect(thumb.count <= ListUpload.limits.thumbBytes)
        let image = try #require(UIImage(data: thumb))
        #expect(max(image.size.width, image.size.height) * image.scale <= CGFloat(ListUpload.limits.thumbPixel))
        #expect(linkItem["aspect"] as? Double != nil)
        #expect((linkItem["tint"] as? String)?.wholeMatch(of: /#[0-9a-f]{6}/) != nil)

        let body = String(decoding: upload.multipart(preview: Data([0xff, 0xd8]), boundary: "B"), as: UTF8.self)
        #expect(body.contains("--B\r\nContent-Disposition: form-data; name=\"list\"\r\nContent-Type: application/json\r\n\r\n{"))
        #expect(body.contains("name=\"\(part)\"; filename=\"\(part).jpg\""))
        #expect(body.contains("name=\"preview\"; filename=\"preview.jpg\""))
        #expect(body.hasSuffix("--B--\r\n"))
    }

    @Test("Makes a square link preview the server accepts")
    func preview() throws {
        let content = ListCardContent(title: "周末要看的", count: 12, entries: (0..<8).map { index in
            index.isMultiple(of: 3)
                ? .init(title: "Remember the milk", site: "Text", isText: true)
                : .init(title: "A post \(index)", site: "example.com", isText: false,
                        image: UIImage(data: photo(CGSize(width: 600, height: index.isMultiple(of: 2) ? 900 : 400))))
        })
        let preview = try #require(ListCardRenderer.previewJPEG(content))
        #expect(preview.count <= 150 * 1024)
        let image = try #require(UIImage(data: preview))
        let width = image.size.width * image.scale, height = image.size.height * image.scale
        #expect((600...1200).contains(width))
        #expect(abs(height - width) <= 1)
    }

    @Test("Reads the server's answers")
    func responses() throws {
        let created = try ListSharingClient.created(
            from: Data(#"{"id":"Ab3xK9mQ2p","url":"https://attentioncard.com/l/Ab3xK9mQ2p","deleteToken":"t"}"#.utf8), status: 201)
        #expect(created.id == "Ab3xK9mQ2p")
        #expect(throws: ListSharingError.dailyLimit) { try ListSharingClient.created(from: Data(#"{"error":"daily_limit"}"#.utf8), status: 429) }
        #expect(throws: ListSharingError.rateLimited) { try ListSharingClient.created(from: Data(#"{"error":"rate_limited"}"#.utf8), status: 429) }
        #expect(throws: ListSharingError.unknownAttestKey) { try ListSharingClient.created(from: Data(#"{"error":"unknown_attest_key"}"#.utf8), status: 401) }
        #expect(throws: ListSharingError.notVerified) { try ListSharingClient.created(from: Data(#"{"error":"attestation_required"}"#.utf8), status: 401) }
        #expect(throws: ListSharingError.uploadsPaused) { try ListSharingClient.created(from: Data(), status: 503) }
        #expect(throws: ListSharingError.rejected) { try ListSharingClient.created(from: Data(), status: 413) }
        #expect(throws: ListSharingError.unavailable) {
            try ListSharingClient.created(from: Data(#"{"id":"x","url":"https://evil.example/l/x","deleteToken":"t"}"#.utf8), status: 201)
        }
    }

    @Test("Clips text the way the server counts it, in Unicode scalars")
    func clipsByScalars() {
        // 240 Swift characters but 360 scalars: each family emoji is one character and five scalars.
        let title = String(repeating: "Thread 👨‍👩‍👧 ", count: 30)
        let clipped = ListUpload.clipped(title, 300)
        #expect(clipped.unicodeScalars.count <= 300)
        #expect(clipped.hasSuffix("…"))
        #expect(clipped.dropLast().allSatisfy { title.contains($0) })
        #expect(ListUpload.clipped("short", 300) == "short")
    }

    @Test("Signs what the server checks: the challenge and the list's JSON")
    func attestClientData() {
        // web/src/attest.ts `uploadClientDataHash` hashes the same string: "<challenge>.<hex SHA-256 of the JSON>".
        let hash = AppAttest.uploadClientDataHash(challenge: "abc", listJSON: Data("{}".utf8))
        let expected = "abc.44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
        #expect(hash == Data(SHA256.hash(data: Data(expected.utf8))))
    }

    @Test("Keeps shared lists to take them down later")
    func records() {
        let library = library()
        library.recordSharedList(SharedListRecord(listID: "Ab3xK9mQ2p", title: "Old", itemCount: 2, deleteToken: "a", createdAt: .now.addingTimeInterval(-60)))
        library.recordSharedList(SharedListRecord(listID: "Zz3xK9mQ2p", title: "New", itemCount: 5, deleteToken: "b"))
        #expect(library.sharedLists().map(\.title) == ["New", "Old"])
        library.removeSharedList(id: "Ab3xK9mQ2p")
        #expect(library.sharedLists().map(\.listID) == ["Zz3xK9mQ2p"])
    }
}
