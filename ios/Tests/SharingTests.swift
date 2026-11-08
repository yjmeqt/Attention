import Testing
import UIKit
import UniformTypeIdentifiers
import LinkPresentation
@testable import Attention

@MainActor
@Suite("Sharing")
struct SharingTests {
    private func accepts(_ attachments: [[String]]) throws -> Bool {
        try acceptsItems([attachments])
    }

    private func acceptsItems(_ items: [[[String]]]) throws -> Bool {
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let url = plugins.appending(path: "AttentionExtension.appex/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let ext = try #require(plist["NSExtension"] as? [String: Any])
        let attributes = try #require(ext["NSExtensionAttributes"] as? [String: Any])
        let rule = try #require(attributes["NSExtensionActivationRule"] as? String)
        return NSPredicate(format: rule).evaluate(with: ["extensionItems": items.map { attachments in
            ["attachments": attachments.map { ["registeredTypeIdentifiers": $0] }]
        }])
    }

    @Test func limitsIncomingAttachments() throws {
        #expect(try accepts([["public.url"]]))
        #expect(try accepts([["public.png"]]))
        #expect(try accepts([["public.plain-text"]]))
        #expect(try !accepts([["public.url"], ["public.url"]]))
        #expect(try !accepts([["public.png"], ["public.png"]]))
        #expect(try !accepts([["com.adobe.pdf"]]))
        #expect(try !accepts([["public.png"], ["com.adobe.pdf"]]))
        #expect(try !accepts([["public.url"], ["public.movie"]]))
        #expect(try accepts([["public.url", "public.plain-text"]]))
        #expect(try accepts([["public.url"], ["public.plain-text"]]))
        #expect(try !accepts([]))
        #expect(try !acceptsItems([]))
        #expect(try acceptsItems([[["public.url"]], [["public.plain-text"]]]))
        #expect(try !acceptsItems([[["public.url"]], [["public.url"]]]))
        #expect(try !acceptsItems([[["public.png"]], [["public.png"]]]))
    }

    @Test func excludesOurOwnShares() throws {
        #expect(try !accepts([["public.url", "com.yjmeqt.attn.shared-url"]]))
        #expect(try !accepts([["public.png", "com.yjmeqt.attn.shared-image"]]))
    }

    private func load(_ provider: NSItemProvider, type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile))
                }
            }
        }
    }

    @Test func urlRepresentationsAndHeader() async throws {
        let url = URL(string: "https://example.com/a?q=hello%20world#section")!
        let item = ShareItem(url: url, title: "Example title", icon: UIImage(systemName: "star"))
        let config = ShareItem.configuration(for: [item])
        #expect(config.itemProvidersForActivityItemsConfiguration.count == 1)
        #expect(item.provider.canLoadObject(ofClass: NSURL.self))
        let standard: URL? = await withCheckedContinuation { continuation in
            _ = item.provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
        let marked = try await load(item.provider, type: UTType("com.yjmeqt.attn.shared-url")!)
        #expect(standard == url)
        #expect(String(data: marked, encoding: .utf8) == url.absoluteString)
        #expect(UTType("com.yjmeqt.attn.shared-url")?.conforms(to: .url) == true)
        let metadata = try #require(config.perItemMetadataProvider?(0, .linkPresentationMetadata) as? LPLinkMetadata)
        #expect(metadata.title == "Example title")
        #expect(metadata.url == url)
        #expect(metadata.originalURL == url)
        #expect(metadata.iconProvider != nil)
    }

    @Test func imageRepresentationsAndHeader() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 6)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        }
        let item = ShareItem(image: image, title: "Image title", url: nil, icon: nil)
        let config = ShareItem.configuration(for: [item])
        #expect(config.itemProvidersForActivityItemsConfiguration.count == 1)
        #expect(item.provider.canLoadObject(ofClass: UIImage.self))
        for type in [UTType.png, UTType("com.yjmeqt.attn.shared-image")!] {
            let data = try await load(item.provider, type: type)
            let decoded = try #require(UIImage(data: data))
            #expect(decoded.cgImage?.width == image.cgImage?.width)
            #expect(decoded.cgImage?.height == image.cgImage?.height)
        }
        #expect(UTType("com.yjmeqt.attn.shared-image")?.conforms(to: .png) == true)
        let metadata = try #require(config.perItemMetadataProvider?(0, .linkPresentationMetadata) as? LPLinkMetadata)
        #expect(metadata.title == "Image title")
        #expect(metadata.imageProvider != nil)
        #expect(config.perItemMetadataProvider?(0, .title) as? String == "Image title")
    }

}
