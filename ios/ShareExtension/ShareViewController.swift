import UIKit
import SwiftUI

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let root = ShareRoot(items: items) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

/// Shows the card maker right away; the shared link can take a moment to load from the host app.
private struct ShareRoot: View {
    let items: [NSExtensionItem]
    let onDone: () -> Void
    @State private var url: URL?
    @State private var loaded = false

    var body: some View {
        if loaded {
            CardMakerView(initialURL: url, onDone: onDone)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    url = await ItemProviders.firstLink(in: items)
                    loaded = true
                }
        }
    }
}
