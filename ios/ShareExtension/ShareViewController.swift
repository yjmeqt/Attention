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
    /// Set when opened from the Save suggestion: the item, shown briefly as a confirmation.
    @State private var savedOnly: LibraryItem?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let savedOnly {
                    ContentUnavailableView {
                        Label("Saved to \(Brand.name)", systemImage: "checkmark.circle.fill")
                            .symbolRenderingMode(.multicolor)
                    } description: {
                        Text(savedOnly.isImage ? String(localized: "Image") : savedOnly.displayTitle)
                            .lineLimit(2)
                    }
                    .symbolEffect(.bounce, value: savedOnly.id)
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
                savedOnly = saved
                // Closes after a second without waiting for the preview: the app fetches
                // previews that are still missing the next time it opens.
                Task { await library.enrich(saved) }
                try? await Task.sleep(for: .seconds(1.2))
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
