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

/// Saves whatever was shared as soon as it's read, then shows it with Share and Done.
private struct ShareRoot: View {
    let items: [NSExtensionItem]
    let onDone: () -> Void
    @State private var library = Library()
    @State private var item: LibraryItem?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let item {
                    ItemDetailView(item: item, library: library, onDone: onDone)
                } else if failed {
                    ContentUnavailableView("Nothing to save", systemImage: "link.badge.plus",
                                           description: Text("No link or image was shared."))
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar {
                if item == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close, action: onDone)
                    }
                }
            }
        }
        .task {
            guard let capture = await Intake.capture(from: items) else {
                failed = true
                return
            }
            let saved = library.save(capture)
            item = saved
            await library.enrich(saved)
        }
    }
}
