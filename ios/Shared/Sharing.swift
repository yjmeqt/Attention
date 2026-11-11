import UIKit
import SwiftUI
import UniformTypeIdentifiers
import LinkPresentation

enum Clipboard {
    private static let ignoredKey = "ignoredPasteboardChangeCount"

    enum Offer: Equatable { case link, text, image }

    /// Marks the current clipboard contents as already handled so they aren't offered again.
    static func ignoreCurrent() {
        AppGroup.defaults.set(UIPasteboard.general.changeCount, forKey: ignoredKey)
    }

    /// Checks for a new link, image or text without reading the clipboard contents.
    static func newOffer() async -> Offer? {
        await offer(on: .general, since: AppGroup.defaults.integer(forKey: ignoredKey))
    }

    static func offer(on pasteboard: UIPasteboard, since ignoredChangeCount: Int) async -> Offer? {
        guard pasteboard.changeCount != ignoredChangeCount else { return nil }
        return await withCheckedContinuation { continuation in
            pasteboard.detectPatterns(for: [\.probableWebURL]) { @Sendable result in
                let found = (try? result.get()) ?? []
                if found.contains(\UIPasteboard.DetectedValues.probableWebURL) {
                    continuation.resume(returning: .link)
                } else if pasteboard.hasImages {
                    continuation.resume(returning: .image)
                } else {
                    continuation.resume(returning: pasteboard.hasStrings ? .text : nil)
                }
            }
        }
    }

    static func copy(_ url: URL, offerToPaste: Bool = false) {
        UIPasteboard.general.setItems([[
            UTType.url.identifier: url,
            UTType.plainText.identifier: url.absoluteString,
        ]])
        if !offerToPaste { ignoreCurrent() }
    }

    static func copy(_ text: String) {
        UIPasteboard.general.string = text
        ignoreCurrent()
    }

    static func copy(_ image: UIImage) {
        UIPasteboard.general.image = image
        ignoreCurrent()
    }
}

/// A shared image or link plus the title and icon the share sheet's header shows for it,
/// so the header reads like the card instead of "PNG Image".
final class ShareItem: NSObject, UIActivityItemSource {
    private let item: Any
    private let metadata: LPLinkMetadata

    init(image: UIImage, title: String, url: URL?, icon: UIImage?) {
        item = image
        metadata = Self.metadata(title: title, url: url, icon: icon)
        metadata.imageProvider = NSItemProvider(object: image)
    }

    init(url: URL, title: String, icon: UIImage?) {
        item = url
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

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { item }

    func activityViewController(_ controller: UIActivityViewController, itemForActivityType type: UIActivity.ActivityType?) -> Any? { item }

    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? { metadata }
}

/// Presents `UIActivityViewController` from the view hierarchy, anchored to a SwiftUI view
/// so it works as a popover on iPad and inside the share extension.
final class SharePresenter {
    weak var anchor: UIView?
    /// Called with the activity when the person finishes an action in the share sheet, not when they cancel it.
    var onCompleted: (UIActivity.ActivityType?) -> Void = { _ in }

    /// Actions that make no sense for a link or a link card.
    private static let excluded: [UIActivity.ActivityType] = [.assignToContact, .print, .openInIBooks, .markupAsPDF]

    func present(_ items: [Any]) {
        guard let anchor, var host = anchor.nearestViewController else { return }
        while let presented = host.presentedViewController { host = presented }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.excludedActivityTypes = Self.excluded
        sheet.completionWithItemsHandler = { [weak self] activity, completed, _, _ in
            self?.finished(activity, completed: completed)
        }
        sheet.popoverPresentationController?.sourceView = anchor
        sheet.popoverPresentationController?.sourceRect = anchor.bounds
        host.present(sheet, animated: true)
    }

    func finished(_ activity: UIActivity.ActivityType?, completed: Bool) {
        if completed { onCompleted(activity) }
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
