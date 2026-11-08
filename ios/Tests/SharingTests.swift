import Testing
import UIKit
import UniformTypeIdentifiers
import LinkPresentation
@testable import Attention

@MainActor
@Suite("Sharing")
struct SharingTests {
    @Test func actionExtensionsAppearInSystemActions() throws {
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        for (name, mode, symbol) in [
            ("AttentionSaveAction", "save", "tray.and.arrow.down"),
            ("AttentionCardAction", "share", "square.and.arrow.up"),
        ] {
            let url = plugins.appending(path: "\(name).appex/Info.plist")
            let data = try Data(contentsOf: url)
            let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            let ext = try #require(plist["NSExtension"] as? [String: Any])
            let attributes = try #require(ext["NSExtensionAttributes"] as? [String: Any])
            #expect(ext["NSExtensionPointIdentifier"] as? String == "com.apple.ui-services")
            #expect(plist["AttentionActionMode"] as? String == mode)
            #expect((plist["CFBundleDisplayName"] as? String)?.isEmpty == false)
            let icons = try #require(plist["CFBundleIcons"] as? [String: Any])
            let primaryIcon = try #require(icons["CFBundlePrimaryIcon"] as? [String: Any])
            #expect(primaryIcon["CFBundleSymbolName"] as? String == symbol)
            let rule = try #require(attributes["NSExtensionActivationRule"] as? String)
            let predicate = NSPredicate(format: rule)
            let input: [String: Any] = ["extensionItems": [["attachments": [["registeredTypeIdentifiers": ["public.url"]]]]]]
            #expect(predicate.evaluate(with: input))
        }
    }

    private func accepts(_ attachments: [[String]]) throws -> Bool {
        try acceptsItems([attachments])
    }

    private func acceptsItems(_ items: [[[String]]], extensionName: String = "AttentionExtension") throws -> Bool {
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let url = plugins.appending(path: "\(extensionName).appex/Info.plist")
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

    @Test func excludesOurOwnTextSharesInEveryExtension() throws {
        for name in ["AttentionExtension", "AttentionSaveAction", "AttentionCardAction"] {
            #expect(try acceptsItems([[["public.utf8-plain-text"]]], extensionName: name))
            #expect(try !acceptsItems([[["public.utf8-plain-text", "com.yjmeqt.attn.shared-text"]]], extensionName: name))
        }
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

    @Test func textRepresentationsPreserveCompleteBody() async throws {
        let body = "  **literal** text\n\nSecond paragraph https://example.com/a\n\tEnd  "
        let item = ShareItem(text: body, title: "Text preview")
        let config = ShareItem.configuration(for: [item])
        #expect(item.provider.canLoadObject(ofClass: NSString.self))
        let standard: String? = await withCheckedContinuation { continuation in
            _ = item.provider.loadObject(ofClass: NSString.self) { value, _ in
                continuation.resume(returning: value as? String)
            }
        }
        #expect(standard == body)
        for type in [UTType.utf8PlainText, try #require(UTType("com.yjmeqt.attn.shared-text"))] {
            #expect(String(data: try await load(item.provider, type: type), encoding: .utf8) == body)
        }
        #expect(UTType("com.yjmeqt.attn.shared-text")?.conforms(to: .utf8PlainText) == true)
        let metadata = try #require(config.perItemMetadataProvider?(0, .linkPresentationMetadata) as? LPLinkMetadata)
        #expect(metadata.title == "Text preview")
        #expect(metadata.url == nil)
        #expect(metadata.originalURL == nil)
        #expect(metadata.imageProvider == nil)
    }

    @Test func copyTextPreservesWhitespace() {
        let body = "  First paragraph\n\nSecond paragraph\n\tLast  "
        Clipboard.copy(body)
        #expect(UIPasteboard.general.string == body)
    }

    @Test func clipboardOfferDistinguishesNewLinksAndText() async {
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        let initialChange = pasteboard.changeCount

        pasteboard.string = "A note without a link"
        #expect(await Clipboard.offer(on: pasteboard, since: initialChange) == .text)
        #expect(await Clipboard.offer(on: pasteboard, since: pasteboard.changeCount) == nil)

        pasteboard.string = "https://example.com/article"
        #expect(await Clipboard.offer(on: pasteboard, since: initialChange) == .link)
    }

    @Test func clipboardOfferDetectsNewImage() async {
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        let initialChange = pasteboard.changeCount
        pasteboard.image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }

        #expect(await Clipboard.offer(on: pasteboard, since: initialChange) == .image)
        #expect(await Clipboard.offer(on: pasteboard, since: pasteboard.changeCount) == nil)
    }

}
