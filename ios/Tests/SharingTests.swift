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

    @Test func noOutgoingMarkerTypesAreExported() {
        let declarations = Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]] ?? []
        #expect(!declarations.contains { ($0["UTTypeIdentifier"] as? String)?.hasPrefix("com.yjmeqt.attn.shared-") == true })
    }

    @Test func urlPayloadAndHeader() throws {
        let url = URL(string: "https://example.com/a?q=hello%20world#section")!
        let item = ShareItem(url: url, title: "Example title", icon: UIImage(systemName: "star"))
        let controller = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        #expect(item.activityViewControllerPlaceholderItem(controller) as? URL == url)
        #expect(item.activityViewController(controller, itemForActivityType: nil) as? URL == url)
        let metadata = try #require(item.activityViewControllerLinkMetadata(controller))
        #expect(metadata.title == "Example title")
        #expect(metadata.url == url)
        #expect(metadata.iconProvider != nil)
    }

    @Test func imageSourceReturnsImageForEveryReceiver() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 6)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        }
        let item = ShareItem(image: image, title: "Card with a link", url: URL(string: "https://example.com"), icon: nil)
        let controller = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        #expect(item.activityViewControllerPlaceholderItem(controller) as? UIImage === image)
        for receiver: UIActivity.ActivityType? in [nil, .message, UIActivity.ActivityType("com.tencent.xin.sharetimeline")] {
            #expect(item.activityViewController(controller, itemForActivityType: receiver) as? UIImage === image)
        }
        let metadata = try #require(item.activityViewControllerLinkMetadata(controller))
        #expect(metadata.title == "Card with a link")
        #expect(metadata.imageProvider != nil)
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
