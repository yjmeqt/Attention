import UIKit
import SwiftUI
import UniformTypeIdentifiers
import LinkPresentation

enum Clipboard {
    private static let ignoredKey = "ignoredPasteboardChangeCount"

    /// Marks the current clipboard contents as already handled so they aren't offered again.
    static func ignoreCurrent() {
        AppGroup.defaults.set(UIPasteboard.general.changeCount, forKey: ignoredKey)
    }

    /// Checks for a link without triggering the paste-permission prompt.
    static func hasNewLink() async -> Bool {
        let pasteboard = UIPasteboard.general
        guard pasteboard.changeCount != AppGroup.defaults.integer(forKey: ignoredKey) else { return false }
        return await withCheckedContinuation { continuation in
            pasteboard.detectPatterns(for: [\.probableWebURL]) { @Sendable result in
                let found = (try? result.get()) ?? []
                continuation.resume(returning: found.contains(\UIPasteboard.DetectedValues.probableWebURL))
            }
        }
    }

    static func copy(_ url: URL) {
        UIPasteboard.general.setItems([[
            UTType.url.identifier: url,
            UTType.plainText.identifier: url.absoluteString,
        ]])
        ignoreCurrent()
    }

    static func copy(_ image: UIImage) {
        UIPasteboard.general.image = image
        ignoreCurrent()
    }
}

/// A shared image or link plus the title and icon the share sheet's header shows for it,
/// so the header reads like the card instead of "PNG Image".
final class ShareItem {
    let provider: NSItemProvider
    private let metadata: LPLinkMetadata

    init(image: UIImage, title: String, url: URL?, icon: UIImage?) {
        provider = NSItemProvider(object: image)
        // A subtype carries real PNG bytes, so receivers can still use standard image types.
        provider.registerDataRepresentation(forTypeIdentifier: "com.yjmeqt.attn.shared-image", visibility: .all) { completion in
            if let data = image.pngData() {
                completion(data, nil)
            } else {
                completion(nil, CocoaError(.fileReadCorruptFile))
            }
            return nil
        }
        metadata = Self.metadata(title: title, url: url, icon: icon)
        metadata.imageProvider = NSItemProvider(object: image)
    }

    init(url: URL, title: String, icon: UIImage?) {
        provider = NSItemProvider(object: url as NSURL)
        provider.registerDataRepresentation(forTypeIdentifier: "com.yjmeqt.attn.shared-url", visibility: .all) { completion in
            completion(Data(url.absoluteString.utf8), nil)
            return nil
        }
        metadata = Self.metadata(title: title, url: url, icon: icon)
    }

    private static func metadata(title: String, url: URL?, icon: UIImage?) -> LPLinkMetadata {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.originalURL = url
        metadata.url = url
        metadata.iconProvider = icon.map { NSItemProvider(object: $0) }
        return metadata
    }

    static func configuration(for items: [ShareItem]) -> UIActivityItemsConfiguration {
        let configuration = UIActivityItemsConfiguration(itemProviders: items.map(\.provider))
        configuration.perItemMetadataProvider = { index, key in
            guard items.indices.contains(index) else { return nil }
            switch key {
            case .linkPresentationMetadata: return items[index].metadata
            case .title: return items[index].metadata.title
            default: return nil
            }
        }
        return configuration
    }
}

/// Presents `UIActivityViewController` from the view hierarchy, anchored to a SwiftUI view
/// so it works as a popover on iPad and inside the share extension.
final class SharePresenter {
    weak var anchor: UIView?

    /// Actions that make no sense for a link or a link card.
    private static let excluded: [UIActivity.ActivityType] = [.assignToContact, .print, .openInIBooks, .markupAsPDF]

    func present(_ items: [ShareItem]) {
        guard let anchor, var host = anchor.nearestViewController else { return }
        while let presented = host.presentedViewController { host = presented }
        let sheet = UIActivityViewController(activityItemsConfiguration: ShareItem.configuration(for: items))
        sheet.excludedActivityTypes = Self.excluded
        sheet.popoverPresentationController?.sourceView = anchor
        sheet.popoverPresentationController?.sourceRect = anchor.bounds
        host.present(sheet, animated: true)
    }
}

struct ShareAnchor: UIViewRepresentable {
    let presenter: SharePresenter

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        presenter.anchor = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        presenter.anchor = view
    }
}

extension UIView {
    var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let controller = next as? UIViewController { return controller }
            responder = next
        }
        return nil
    }
}
