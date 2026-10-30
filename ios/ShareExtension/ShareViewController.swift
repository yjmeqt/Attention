import UIKit
import SwiftUI

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let suggestion = ShareSuggestion(intent: extensionContext?.intent)
        let root = ShareRoot(items: items, suggestion: suggestion) { [weak self] in
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
/// Opened from the Save suggestion it only confirms the save and closes; from Share,
/// it waits for the card and opens the share sheet with it.
private struct ShareRoot: View {
    let items: [NSExtensionItem]
    let suggestion: ShareSuggestion?
    let onDone: () -> Void
    @State private var library = Library()
    @State private var item: LibraryItem?
    @State private var savedOnly = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if savedOnly {
                    ContentUnavailableView("Saved to \(Brand.name)", systemImage: "checkmark.circle.fill")
                } else if let item {
                    ItemDetailView(item: item, library: library, autoShare: suggestion == .share, onDone: onDone)
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
            switch suggestion {
            case .save:
                ShareSuggestion.save.donate()
                savedOnly = true
                // Keeps the confirmation up for at least a second, longer if the preview takes longer.
                let shown = ContinuousClock.now
                await library.enrich(saved)
                try? await Task.sleep(until: shown + .seconds(1))
                onDone()
            case .share:
                await library.enrich(saved)
                item = saved
            case nil:
                ShareSuggestion.save.donate()
                item = saved
                await library.enrich(saved)
            }
        }
    }
}
