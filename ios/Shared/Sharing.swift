import UIKit
import SwiftUI
import UniformTypeIdentifiers

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
}

/// Presents `UIActivityViewController` from the view hierarchy, anchored to a SwiftUI view
/// so it works as a popover on iPad and inside the share extension.
final class SharePresenter {
    weak var anchor: UIView?

    func present(_ items: [Any]) {
        guard let anchor, var host = anchor.nearestViewController else { return }
        while let presented = host.presentedViewController { host = presented }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
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
