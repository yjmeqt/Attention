import Photos
import SwiftUI

/// Actions available on a saved item, shared by the feed's long-press menu and the detail page.
@Observable
final class ItemActions {
    let library: Library
    @ObservationIgnored let presenter = SharePresenter()
    var browser: BrowserLink?
    var tagTargets: [LibraryItem]?
    var textTarget: LibraryItem?
    var pendingDelete: [LibraryItem]?
    var notice: Notice?
    /// While Private is unlocked, removing items from it doesn't ask for Face ID again.
    var privateUnlocked = false
    var showsPasscodeRequired = false
    @ObservationIgnored var onDeleted: ([LibraryItem]) -> Void = { _ in }
    @ObservationIgnored var onArchived: ([LibraryItem]) -> Void = { _ in }

    init(library: Library) {
        self.library = library
        presenter.onCompleted = { [weak self] in self?.succeeded() }
    }

    /// A share or save went through: a good moment to ask for a rating, now and then.
    private func succeeded() {
        ReviewPrompt.success(in: presenter.anchor?.window?.windowScene)
    }

    enum Notice { case textCopied, linkCopied, linkCopiedForImage, imageCopied, savedToPhotos, photosDenied, photosSaveFailed }

    func shareLink(_ item: LibraryItem) {
        guard library.contains(item) else { return }
        guard let url = shareURL(item) else { return }
        presenter.present([ShareItem(url: url, title: item.displayTitle, icon: library.favicon(item))])
    }

    func copyLink(_ item: LibraryItem) {
        guard library.contains(item) else { return }
        guard let url = shareURL(item) else { return }
        Clipboard.copy(url)
        notice = .linkCopied
    }

    func copyText(_ item: LibraryItem) {
        guard library.contains(item), let text = item.text else { return }
        Clipboard.copy(text)
        notice = .textCopied
    }

    func shareText(_ item: LibraryItem) {
        guard library.contains(item), let text = item.text else { return }
        // Plain text is a single native share item, without link-preview metadata.
        presenter.present([text])
    }

    func copyImage(_ item: LibraryItem) {
        guard library.contains(item) else { return }
        guard let image = library.fullImage(item) else { return }
        Clipboard.copy(image)
        notice = .imageCopied
    }

    func saveToPhotos(_ item: LibraryItem) async {
        guard library.contains(item) else { return }
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
            succeeded()
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
        guard library.contains(item) else { return }
        guard let image = library.fullImage(item) else { return }
        let url = shareURL(item)
        if let url {
            Clipboard.copy(url)
            notice = .linkCopiedForImage
        }
        presenter.present([ShareItem(image: image, title: item.displayTitle, url: url, icon: library.favicon(item))])
        ShareSuggestion.share.donate()
    }

    /// Shares the link, full text or rendered image according to the saved preference.
    func share(_ item: LibraryItem, _ preference: ShareDefault) {
        guard library.contains(item) else { return }
        switch preference.format(for: item) {
        case .text: shareText(item)
        case .link: shareLink(item)
        case .image: shareImage(item)
        }
    }

    private func shareURL(_ item: LibraryItem) -> URL? {
        library.meta(for: item)?.shareURL ?? item.url
    }

    func openInBrowser(_ item: LibraryItem) {
        guard library.contains(item) else { return }
        guard let url = item.url else { return }
        browser = BrowserLink(url: url)
    }

    func openInApp(_ item: LibraryItem) {
        guard library.contains(item) else { return }
        guard let url = item.url else { return }
        Opening.openInApp(url) { [weak self] in self?.browser = BrowserLink(url: url) }
    }

    func editTags(_ items: [LibraryItem]) { tagTargets = items }

    func editText(_ item: LibraryItem) {
        guard library.contains(item), item.hasText else { return }
        textTarget = item
    }

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
        guard !Task.isCancelled else { return }
        library.setPrivate(isPrivate, items.filter { library.contains($0) })
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

/// The feed's long-press menu: quick actions only. Opening is a tap on the card, and tags and selection
/// live on the detail page and in More.
struct ItemMenu: View {
    let item: LibraryItem
    let actions: ItemActions
    @AppStorage(ShareDefault.key, store: AppGroup.defaults) private var shareDefault = ShareDefault.initial

    var body: some View {
        Section {
            Button("Share", systemImage: "square.and.arrow.up") { actions.share(item, shareDefault) }
            if item.hasText {
                Button("Edit Text", systemImage: "pencil") { actions.editText(item) }
                Button("Copy Text", systemImage: "doc.on.doc") { actions.copyText(item) }
                if !item.isTextOnly {
                    Button("Share Text", systemImage: "text.alignleft") { actions.shareText(item) }
                }
            }
            if item.url != nil {
                Button("Copy Link", systemImage: "doc.on.doc") { actions.copyLink(item) }
            }
        }
        Section {
            if item.isPrivate {
                Button("Remove from Private", systemImage: "lock.open") { Task { await actions.setPrivate(false, [item]) } }
            } else {
                Button("Move to Private", systemImage: "lock") { Task { await actions.setPrivate(true, [item]) } }
            }
            if item.isArchived {
                Button("Unarchive", systemImage: "tray.and.arrow.up") { actions.setArchived(false, [item]) }
            } else {
                Button("Archive", systemImage: "archivebox") { actions.setArchived(true, [item]) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { actions.delete([item]) }
        }
    }
}

/// What tapping Share shares, set in Settings. Kept in the app group so the share extension follows it too.
enum ShareDefault: String, CaseIterable {
    case link, image

    static let key = "shareDefault"
    static let initial: Self = .image

    enum Format { case text, link, image }

    func format(for item: LibraryItem) -> Format {
        if self == .image { return .image }
        if item.isTextOnly { return .text }
        return item.url == nil ? .image : .link
    }
}

/// Share Link, Copy Link and Share as Image; a single Share button for image items, which have no link.
struct ShareMenu<MenuLabel: View>: View {
    let item: LibraryItem
    let actions: ItemActions
    /// Tapping shares the way Settings says; the menu opens on a long press.
    var sharesOnTap = false
    @ViewBuilder var label: () -> MenuLabel
    @AppStorage(ShareDefault.key, store: AppGroup.defaults) private var shareDefault = ShareDefault.initial

    var body: some View {
        if item.url == nil && !item.hasText {
            Button { actions.shareImage(item) } label: { label() }
        } else if sharesOnTap {
            Menu {
                options
            } label: {
                label()
            } primaryAction: {
                actions.share(item, shareDefault)
            }
        } else {
            Menu {
                options
            } label: {
                label()
            }
        }
    }

    @ViewBuilder
    private var options: some View {
        if item.hasText {
            Button("Share Text", systemImage: "text.alignleft") { actions.shareText(item) }
            Button("Copy Text", systemImage: "doc.on.doc") { actions.copyText(item) }
        }
        if item.url != nil {
            Button("Share Link", systemImage: "link") { actions.shareLink(item) }
            Button("Copy Link", systemImage: "doc.on.doc") { actions.copyLink(item) }
        }
        Button("Share as Image", systemImage: "photo") { actions.shareImage(item) }
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
            .sheet(item: $actions.browser) { link in
                SafariView(url: link.url).ignoresSafeArea()
            }
            .sheet(item: $actions.textTarget) { item in
                SavedTextEditor(library: actions.library, item: item)
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
