#if DEBUG
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Temporary, offline sharing experiment. Launch with `-shareProbe YES`.
struct ShareProbeView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ShareProbeController { ShareProbeController() }
    func updateUIViewController(_ controller: ShareProbeController, context: Context) {}
}

final class ShareProbeController: UIViewController {
    static let marker = "com.yjmeqt.attn.share-origin"
    private let status = UILabel()
    private let url = URL(string: "https://www.apple.com/swift/?attention_share_probe=1")!
    private lazy var sampleImage = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480)).image { context in
        UIColor.systemTeal.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        ("ATTENTION SHARE PROBE\n640 x 480\nNo personal data" as NSString).draw(
            in: CGRect(x: 30, y: 80, width: 580, height: 300),
            withAttributes: [.font: UIFont.systemFont(ofSize: 32, weight: .bold), .foregroundColor: UIColor.white])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
        ])
        let title = UILabel()
        title.text = "Share compatibility experiment"
        title.font = .preferredFont(forTextStyle: .headline)
        stack.addArrangedSubview(title)
        for mode in ["Baseline", "Exclude ID", "Extra marker", "Provider baseline", "Provider marker", "Typed marker"] {
            for isImage in [false, true] {
                let button = UIButton(type: .system)
                button.configuration = .bordered()
                button.setTitle("\(mode): \(isImage ? "image" : "link")", for: .normal)
                button.addAction(UIAction { [weak self, weak button] _ in
                    guard let self, let button else { return }
                    self.share(mode: mode, isImage: isImage, from: button)
                }, for: .touchUpInside)
                stack.addArrangedSubview(button)
            }
        }
        status.numberOfLines = 0
        status.font = .preferredFont(forTextStyle: .footnote)
        status.text = "No share completed yet."
        stack.addArrangedSubview(status)
    }

    private func share(mode: String, isImage: Bool, from button: UIButton) {
        let item = isImage
            ? ShareItem(image: sampleImage, title: "Attention share probe", url: url, icon: nil)
            : ShareItem(url: url, title: "Attention share probe", icon: nil)
        let sheet: UIActivityViewController
        if mode.hasPrefix("Provider") || mode == "Typed marker" {
            let provider = isImage ? NSItemProvider(object: sampleImage) : NSItemProvider(object: url as NSURL)
            if mode != "Provider baseline" {
                // The typed variant conforms to the real payload type and supplies real bytes.
                let type = mode == "Typed marker"
                    ? (isImage ? "com.yjmeqt.attn.shared-image" : "com.yjmeqt.attn.shared-url") : Self.marker
                let data = mode == "Typed marker"
                    ? (isImage ? sampleImage.pngData()! : Data(url.absoluteString.utf8)) : Data("Attention".utf8)
                provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
            }
            sheet = UIActivityViewController(activityItemsConfiguration: UIActivityItemsConfiguration(itemProviders: [provider]))
        } else {
            var items: [Any] = [item]
            if mode == "Extra marker" { items.append(ShareProbeMarker()) }
            sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        }
        sheet.excludedActivityTypes = [.assignToContact, .print, .openInIBooks, .markupAsPDF]
        if mode == "Exclude ID" {
            sheet.excludedActivityTypes?.append(UIActivity.ActivityType(rawValue: "com.yjmeqt.attn.dev.share"))
        }
        sheet.completionWithItemsHandler = { [weak self] activity, completed, _, error in
            self?.status.text = "\(mode), \(isImage ? "image" : "link")\n\(activity?.rawValue ?? "cancelled")\ncompleted=\(completed), error=\(error?.localizedDescription ?? "none")"
        }
        sheet.popoverPresentationController?.sourceView = button
        sheet.popoverPresentationController?.sourceRect = button.bounds
        present(sheet, animated: true)
    }
}

private final class ShareProbeMarker: NSObject, UIActivityItemSource {
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { "" }
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { NSObject() }
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String { ShareProbeController.marker }
}
#endif
