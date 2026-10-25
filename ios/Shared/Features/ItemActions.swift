import SwiftUI

/// Actions available on a saved item, shared by the feed's long-press menu and the detail page.
@Observable
final class ItemActions {
    let library: Library
    @ObservationIgnored let presenter = SharePresenter()
    var browser: BrowserLink?
    var tagTargets: [LibraryItem]?
    var pendingDelete: [LibraryItem]?
    var linkCopied = false
    /// While Private is unlocked, removing items from it doesn't ask for Face ID again.
    var privateUnlocked = false
    var showsPasscodeRequired = false
    @ObservationIgnored var onDeleted: ([LibraryItem]) -> Void = { _ in }

    init(library: Library) { self.library = library }

    func share(_ item: LibraryItem) {
        guard let image = library.fullImage(item) else { return }
        if let meta = library.meta(for: item) {
            Clipboard.copy(meta.shareURL)
            linkCopied = true
        }
        presenter.present([image])
    }

    func openInBrowser(_ item: LibraryItem) {
        guard let url = item.url else { return }
        browser = BrowserLink(url: url)
    }

    func openInApp(_ item: LibraryItem) {
        guard let url = item.url else { return }
        Opening.openInApp(url) { [weak self] in self?.browser = BrowserLink(url: url) }
    }

    func editTags(_ items: [LibraryItem]) { tagTargets = items }

    func setPrivate(_ isPrivate: Bool, _ items: [LibraryItem]) async {
        if !isPrivate, !privateUnlocked {
            switch await DeviceOwner.authenticate(reason: String(localized: "Remove items from Private")) {
            case .authenticated: break
            case .failed: return
            case .unavailable:
                showsPasscodeRequired = true
                return
            }
        }
        library.setPrivate(isPrivate, items)
    }

    func delete(_ items: [LibraryItem]) { pendingDelete = items }

    fileprivate func confirmDelete() {
        guard let items = pendingDelete else { return }
        pendingDelete = nil
        onDeleted(items)
        library.delete(items)
    }
}

struct ItemMenu: View {
    let item: LibraryItem
    let actions: ItemActions
    var filter: FeedFilter?
    var onSelect: (() -> Void)?

    var body: some View {
        if item.url != nil {
            Section {
                if Opening.canOpenApps {
                    Button("Open in App", systemImage: "arrow.up.forward.app") { actions.openInApp(item) }
                }
                Button("Open in Browser", systemImage: "safari") { actions.openInBrowser(item) }
            }
        }
        Button("Share", systemImage: "square.and.arrow.up") { actions.share(item) }
        if let filter {
            Menu("Filter", systemImage: "line.3.horizontal.decrease") {
                Button(String(localized: "Only \(item.domainLabel)")) { filter.only(domain: item.domain) }
                ForEach(item.tags, id: \.self) { tag in
                    Button(String(localized: "Only #\(tag)")) { filter.only(tag: tag) }
                }
            }
        }
        Section {
            Button("Edit Tags…", systemImage: "tag") { actions.editTags([item]) }
            if item.isPrivate {
                Button("Remove from Private", systemImage: "lock.open") { Task { await actions.setPrivate(false, [item]) } }
            } else {
                Button("Move to Private", systemImage: "lock") { Task { await actions.setPrivate(true, [item]) } }
            }
            if let onSelect {
                Button("Select", systemImage: "checkmark.circle", action: onSelect)
            }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { actions.delete([item]) }
    }
}

extension View {
    /// The sheets, dialogs and share anchor that `ItemActions` presents.
    func itemActionPresentations(_ actions: ItemActions) -> some View {
        modifier(ItemActionPresentations(actions: actions))
    }
}

private struct ItemActionPresentations: ViewModifier {
    @Bindable var actions: ItemActions

    func body(content: Content) -> some View {
        content
            .background(ShareAnchor(presenter: actions.presenter))
            .fullScreenCover(item: $actions.browser) { link in
                SafariView(url: link.url).ignoresSafeArea()
            }
            .sheet(isPresented: Binding(get: { actions.tagTargets != nil }, set: { if !$0 { actions.tagTargets = nil } })) {
                if let targets = actions.tagTargets {
                    TagEditor(library: actions.library, items: targets)
                        .presentationDetents([.medium, .large])
                }
            }
            .alert("Set a passcode first", isPresented: $actions.showsPasscodeRequired) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Private items are protected by Face ID or your passcode. Turn on a passcode in Settings to use Private.")
            }
            .confirmationDialog(
                deleteTitle,
                isPresented: Binding(get: { actions.pendingDelete != nil }, set: { if !$0 { actions.pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { actions.confirmDelete() }
            }
    }

    private var deleteTitle: String {
        let count = actions.pendingDelete?.count ?? 0
        return count == 1 ? String(localized: "Delete this item?") : String(localized: "Delete \(count) items?")
    }
}
