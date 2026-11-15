import Foundation
import Testing
@testable import Attention

@MainActor
@Suite("Shared lists")
struct SharedListTests {
    @Test("Recognizes shared-list links on both hosts")
    func links() {
        #expect(SharedListLink(url: URL(string: "https://attentioncard.com/l/Ab3xK9mQ2p")!)?.id == "Ab3xK9mQ2p")
        #expect(SharedListLink(url: URL(string: "https://open.attentioncard.com/l/Ab3xK9mQ2p/")!)?.id == "Ab3xK9mQ2p")
        #expect(SharedListLink(url: URL(string: "https://ATTENTIONCARD.COM/l/Ab3xK9mQ2p")!) != nil)
        for other in [
            "http://attentioncard.com/l/Ab3xK9mQ2p",
            "https://attentioncard.com/l/Ab3xK9mQ2p/0.jpg",
            "https://attentioncard.com/l/short",
            "https://attentioncard.com/privacy",
            "https://evil.example/l/Ab3xK9mQ2p",
            "https://attentioncard.com.evil.example/l/Ab3xK9mQ2p",
        ] {
            #expect(SharedListLink(url: URL(string: other)!) == nil, "\(other)")
        }
        #expect(SharedListLink(url: URL(string: "https://open.attentioncard.com/l/Ab3xK9mQ2p")!)?.apiURL.absoluteString
            == "https://attentioncard.com/api/lists/Ab3xK9mQ2p")
    }

    /// The shape web/src/index.ts (`listJSON`) returns.
    static let json = Data("""
    {"id":"Ab3xK9mQ2p","url":"https://attentioncard.com/l/Ab3xK9mQ2p","title":"Weekend","lang":"en",
     "createdAt":"2026-11-14T08:00:00.000Z",
     "items":[
       {"kind":"link","url":"https://youtu.be/abc","title":"A video","site":"YouTube","author":"Someone",
        "thumb":"https://attentioncard.com/l/Ab3xK9mQ2p/0.jpg","aspect":1.78},
       {"kind":"text","text":"Remember the milk"},
       {"kind":"link","url":"https://example.com/post","title":"","site":""}
     ]}
    """.utf8)

    @Test("Decodes the server's list and errors")
    func decoding() throws {
        let list = try SharedListClient.list(from: Self.json, status: 200)
        #expect(list.title == "Weekend")
        #expect(list.items.count == 3)
        #expect(list.items[0].thumb?.absoluteString == "https://attentioncard.com/l/Ab3xK9mQ2p/0.jpg")
        #expect(list.items[1].kind == .text)
        #expect(list.links.count == 2)
        #expect(list.createdAt == ISO8601DateFormatter().date(from: "2026-11-14T08:00:00Z"))

        #expect(throws: SharedListError.gone) { try SharedListClient.list(from: Data(#"{"error":"revoked"}"#.utf8), status: 410) }
        #expect(throws: SharedListError.notFound) { try SharedListClient.list(from: Data(), status: 404) }
        #expect(throws: SharedListError.unavailable) { try SharedListClient.list(from: Data("nope".utf8), status: 200) }
    }

    @Test("Saves links and texts, tagged with the list's title, without duplicating")
    func saving() throws {
        let library = Library(directory: .temporaryDirectory.appending(path: UUID().uuidString), inMemory: true)
        let existing = library.save(Capture(url: URL(string: "https://youtu.be/abc")!))
        library.addTag("Mine", to: [existing])

        let list = try SharedListClient.list(from: Self.json, status: 200)
        let saved = library.save(list)

        #expect(saved.count == 3)
        #expect(library.items.count == 3)
        #expect(saved.allSatisfy { $0.tags.contains(Library.normalizedTag("Weekend")) })
        #expect(existing.tags.contains("Mine"))
        #expect(saved.contains { $0.text == "Remember the milk" })
    }
}
