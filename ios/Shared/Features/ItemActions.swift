import Photos
import SwiftUI

/// Actions available on a saved item, shared by the feed's long-press menu and the detail page.
@Observable
final class ItemActions {
    let library: Library
    @ObservationIgnored let presenter = SharePresenter()
    var browser: BrowserLink?
    var tagTargets: [LibraryItem]?
    var pendingDelete: [LibraryItem]?
    var notice: Notice?
    /// While Private is unlocked, removing items from it doesn't ask for Face ID again.
    var privateUnlocked = false
    var showsPasscodeRequired = false
    @ObservationIgnored var onDeleted: ([LibraryItem]) -> Void = { _ in }
    @ObservationIgnored var onArchived: ([LibraryItem]) -> Void = { _ in }

    init(library: Library) { self.library = library }

    enum Notice { case linkCopied, linkCopiedForImage, imageCopied, savedToPhotos, photosDenied, photosSaveFailed }

    func shareLink(_ item: LibraryItem) {
        guard let url = shareURL(item) else { return }
        presenter.present([ShareItem(url: url, title: item.displayTitle, icon: library.favicon(item))])
    }

    func copyLink(_ item: LibraryItem) {
        guard let url = shareURL(item) else { return }
        Clipboard.copy(url)
        notice = .linkCopied
    }

    func copyImage(_ item: LibraryItem) {
        guard let image = library.fullImage(item) else { return }
        Clipboard.copy(image)
        notice = .imageCopied
    }

    func saveToPhotos(_ item: LibraryItem) async {
        guard let image = library.fullImage(item) else { return }
        switch await PHPhotoLibrary.requestAuthorization(for: .addOnly) {
        case .authorized, .limited: break
        default:
            notice = .photosDenied
            return
        }
        do {
            try await Self.addToPhotos(image)
            notice = .savedToPhotos
        } catch {
            notice = .photosSaveFailed
        }
    }

    /// Photos runs the change block on its own queue, so it mustn't be main-actor isolated.
    private nonisolated static func addToPhotos(_ image: UIImage) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }

    func shareImage(_ item: LibraryItem) {
        guard let image = library.fullImage(item) else { return }
        let url = shareURL(item)
        if let url {
            Clipboard.copy(url)
            notice = .linkCopiedForImage
        }
        presenter.present([ShareItem(image: image, title: item.displayTitle, url: url, icon: library.favicon(item))])
        ShareSuggestion.share.donate()
    }

    private func shareURL(_ item: LibraryItem) -> URL? {
        library.meta(for: item)?.shareURL ?? item.url
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

    func setArchived(_ isArchived: Bool, _ items: [LibraryItem]) {
        library.setArchived(isArchived, items)
        onArchived(items)
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
        ShareMenu(item: item, actions: actions)
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
        Section {
            if item.isArchived {
                Button("Unarchive", systemImage: "tray.and.arrow.up") { actions.setArchived(false, [item]) }
            } else {
                Button("Archive", systemImage: "archivebox") { actions.setArchived(true, [item]) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { actions.delete([item]) }
        }
    }
}

/// Share Link, Copy Link and Share as Image; a single Share button for image items, which have no link.
struct ShareMenu<MenuLabel: View>: View {
    let item: LibraryItem
    let actions: ItemActions
    @ViewBuilder var label: () -> MenuLabel

    var body: some View {
        if item.url == nil {
            Button { actions.shareImage(item) } label: { label() }
        } else {
            Menu {
                Button("Share Link", systemImage: "link") { actions.shareLink(item) }
                Button("Copy Link", systemImage: "doc.on.doc") { actions.copyLink(item) }
                Button("Share as Image", systemImage: "photo") { actions.shareImage(item) }
            } label: {
                label()
            }
        }
    }
}

extension ShareMenu where MenuLabel == Label<Text, Image> {
    init(item: LibraryItem, actions: ItemActions) {
        self.init(item: item, actions: actions) { Label("Share", systemImage: "square.and.arrow.up") }
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
