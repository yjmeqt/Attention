import SwiftUI

/// The Mac library: sections, sites and tags in the sidebar, the feed as a grid, the selected item in the inspector.
struct LibraryView: View {
    let library: Library

    @State private var filter = FeedFilter()
    @State private var section: Section? = .all
    @State private var selection: UUID?
    @State private var showsInspector = false
    @State private var columns = 3
    @State private var tagTargets: [LibraryItem]?
    @State private var pendingDelete: [LibraryItem]?
    @State private var notice: String?
    @State private var showsPasscodeRequired = false

    typealias Section = FeedFilter.Scope

    private var visible: [LibraryItem] { filter.apply(library.items) }
    private var selectedItem: LibraryItem? { selection.flatMap { id in library.items.first { $0.id == id } } }
    private var actions: LibraryActions {
        LibraryActions(library: library, tagTargets: $tagTargets, pendingDelete: $pendingDelete, notice: $notice,
                       showsPasscodeRequired: $showsPasscodeRequired, privateUnlocked: filter.privateUnlocked)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 300)
        } detail: {
            feed
                .inspector(isPresented: $showsInspector) {
                    Group {
                        if let item = selectedItem {
                            ItemInspector(item: item, actions: actions)
                        } else {
                            ContentUnavailableView("No Selection", systemImage: "rectangle.on.rectangle")
                        }
                    }
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 460)
                }
        }
        .searchable(text: $filter.search, placement: .sidebar)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Paste Link", systemImage: "plus") { pasteFromClipboard() }
                    .help("Save the link or image on the clipboard (⌘V)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Inspector", systemImage: "sidebar.trailing") { showsInspector.toggle() }
            }
        }
        .onChange(of: section) { old, new in select(new, from: old) }
        .onChange(of: selection) { _, id in if id != nil { showsInspector = true } }
        .sheet(isPresented: Binding(get: { tagTargets != nil }, set: { if !$0 { tagTargets = nil } })) {
            if let tagTargets {
                TagEditor(library: library, items: tagTargets).frame(minWidth: 320, minHeight: 360)
            }
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                guard let doomed = pendingDelete else { return }
                if doomed.contains(where: { $0.id == selection }) { selection = nil }
                library.delete(doomed)
                pendingDelete = nil
            }
        }
        .alert("Set a password first", isPresented: $showsPasscodeRequired) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Private items are protected by Touch ID or your login password.")
        }
        .overlay(alignment: .bottom) { noticeView }
        .task { await library.retryMissingPreviews() }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.screensDidSleepNotification)) { _ in lockPrivate() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        let live = library.items.filter(FeedFilter.isLive)
        return List(selection: $section) {
            SwiftUI.Section {
                Label("All Items", systemImage: "square.grid.2x2").tag(Section.all)
                Label("Archived", systemImage: "archivebox").tag(Section.archived)
                Label("Private", systemImage: filter.privateUnlocked ? "lock.open" : "lock").tag(Section.locked)
            }
            let sites = FeedFilter.ranked(live.map(\.domain))
            if !sites.isEmpty {
                SwiftUI.Section("Sites") {
                    ForEach(sites.prefix(30), id: \.self) { domain in
                        Label {
                            Text(DomainTag.label(domain))
                        } icon: {
                            if let item = live.first(where: { $0.domain == domain }), let icon = library.favicon(item) {
                                Image(platformImage: icon).resizable().scaledToFit()
                                    .clipShape(.rect(cornerRadius: 3))
                            } else {
                                Image(systemName: domain == DomainTag.images ? "photo" : "globe")
                            }
                        }
                        .tag(Section.site(domain))
                    }
                }
            }
            let tags = FeedFilter.ranked(live.flatMap(\.tags))
            if !tags.isEmpty {
                SwiftUI.Section("Tags") {
                    ForEach(tags, id: \.self) { tag in
                        Label(tag, systemImage: "number").tag(Section.tag(tag))
                    }
                }
            }
        }
    }

    private var title: String {
        switch section {
        case .all, nil: Brand.name
        case .archived: String(localized: "Archived")
        case .locked: String(localized: "Private")
        case let .site(domain): DomainTag.label(domain)
        case let .tag(tag): "#\(tag)"
        }
    }

    private func select(_ new: Section?, from old: Section?) {
        if new == .locked {
            unlockPrivate(fallback: old)
        } else {
            lockPrivate()
            filter.scope = new ?? .all
        }
        if let selectedItem, !visible.contains(where: { $0.id == selectedItem.id }) { selection = nil }
    }

    private func unlockPrivate(fallback: Section?) {
        filter.scope = .locked
        Task {
            switch await DeviceOwner.authenticate(reason: String(localized: "Show your private items")) {
            case .authenticated:
                filter.privateUnlocked = true
            case .failed:
                section = fallback ?? .all
            case .unavailable:
                showsPasscodeRequired = true
                section = fallback ?? .all
            }
        }
    }

    private func lockPrivate() {
        filter.privateUnlocked = false
        if section == .locked { section = .all }
        if selectedItem?.isPrivate == true { selection = nil }
    }

    // MARK: - Feed

    @ViewBuilder
    private var feed: some View {
        ScrollView {
            if filter.showsPrivate && !filter.privateUnlocked {
                ContentUnavailableView("Private is locked", systemImage: "lock.fill")
                    .padding(.top, 120)
            } else if visible.isEmpty {
                empty.padding(.top, 120)
            } else {
                Waterfall(items: visible, columns: columns, spacing: 14) { tile($0) }
                    .padding(16)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columns = Waterfall<EmptyView>.columns(for: $0) }
        .contentShape(.rect)
        .onTapGesture { selection = nil }
        .onDrop(of: ItemProviders.pasteTypes, isTargeted: nil) { providers in
            save(providers)
            return true
        }
        .onPasteCommand(of: ItemProviders.pasteTypes) { save($0) }
        .onDeleteCommand { if let selectedItem { pendingDelete = [selectedItem] } }
        .onCopyCommand { selectedItem.flatMap(actions.dragProvider).map { [$0] } ?? [] }
    }

    @ViewBuilder
    private var empty: some View {
        if !filter.search.isEmpty {
            ContentUnavailableView.search(text: filter.search)
        } else if filter.isAll {
            ContentUnavailableView {
                Label("No saved links yet", systemImage: "link")
            } description: {
                Text("Paste a link with ⌘V, drop one here, or copy a link anywhere and press \(Hotkey.label).")
            } actions: {
                Button("Paste Link") { pasteFromClipboard() }
            }
        } else {
            ContentUnavailableView(filter.showsArchived ? "No archived items" : filter.showsPrivate ? "No private items" : "Nothing here",
                                   systemImage: filter.showsArchived ? "archivebox" : "tray")
        }
    }

    private func tile(_ item: LibraryItem) -> some View {
        FeedTile(item: item, library: library)
            .overlay {
                if selection == item.id {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.tint, lineWidth: 3)
                }
            }
            .onTapGesture(count: 2) { actions.open(item) }
            .onTapGesture { selection = item.id }
            .onDrag { actions.dragProvider(item) ?? NSItemProvider() }
            .contextMenu { ItemContextMenu(item: item, actions: actions) }
    }

    // MARK: - Intake

    private func pasteFromClipboard() {
        save(NSPasteboard.general.pasteboardItems?.compactMap { item in
            let provider = NSItemProvider()
            for type in item.types {
                guard let data = item.data(forType: type) else { continue }
                provider.registerDataRepresentation(forTypeIdentifier: type.rawValue, visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
            }
            return provider
        } ?? [])
    }

    private func save(_ providers: [NSItemProvider]) {
        Task {
            guard let capture = await Intake.capture(from: providers) else {
                notice = String(localized: "No link found on the clipboard.")
                return
            }
            let item = library.save(capture)
            if item.isPrivate {
                notice = String(localized: "Already saved in Private.")
            } else {
                section = .all
                selection = item.id
            }
            await library.enrich(item)
        }
    }

    // MARK: - Notices

    @ViewBuilder
    private var noticeView: some View {
        if let notice {
            Text(notice)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 16)
                .task(id: notice) {
                    try? await Task.sleep(for: .seconds(3))
                    self.notice = nil
                }
        }
    }

    private var deleteTitle: String {
        let count = pendingDelete?.count ?? 0
        return count == 1 ? String(localized: "Delete this item?") : String(localized: "Delete \(count) items?")
    }
}

/// What the grid's menus and the inspector do to an item.
struct LibraryActions {
    let library: Library
    @Binding var tagTargets: [LibraryItem]?
    @Binding var pendingDelete: [LibraryItem]?
    @Binding var notice: String?
    @Binding var showsPasscodeRequired: Bool
    let privateUnlocked: Bool

    func shareURL(_ item: LibraryItem) -> URL? { library.meta(for: item)?.shareURL ?? item.url }

    func open(_ item: LibraryItem) {
        if let url = item.url { NSWorkspace.shared.open(url) }
    }

    func copyLink(_ item: LibraryItem) {
        guard let url = shareURL(item) else { return }
        MacClipboard.copy(url)
        notice = String(localized: "Link copied")
    }

    func copyImage(_ item: LibraryItem) {
        guard let image = library.fullImage(item) else { return }
        MacClipboard.copy(image)
        notice = String(localized: "Image copied")
    }

    func saveImage(_ item: LibraryItem) {
        guard let image = library.fullImage(item) else { return }
        CardFile.save(image, for: item)
    }

    /// The card as a PNG file, plus the link, so a drop works in chats, Finder and browsers alike.
    func dragProvider(_ item: LibraryItem) -> NSItemProvider? {
        guard let image = library.fullImage(item), let file = CardFile.write(image, for: item) else { return nil }
        let provider = NSItemProvider(contentsOf: file) ?? NSItemProvider()
        if let url = shareURL(item) { provider.registerObject(url as NSURL, visibility: .all) }
        return provider
    }

    func setPrivate(_ isPrivate: Bool, _ item: LibraryItem) {
        Task {
            if !isPrivate, !privateUnlocked {
                switch await DeviceOwner.authenticate(reason: String(localized: "Remove items from Private")) {
                case .authenticated: break
                case .failed: return
                case .unavailable:
                    showsPasscodeRequired = true
                    return
                }
            }
            library.setPrivate(isPrivate, [item])
        }
    }
}

struct ItemContextMenu: View {
    let item: LibraryItem
    let actions: LibraryActions

    var body: some View {
        if item.url != nil {
            Button("Open in Browser", systemImage: "safari") { actions.open(item) }
            Divider()
            Button("Copy Link", systemImage: "link") { actions.copyLink(item) }
        }
        Button("Copy Image", systemImage: "photo") { actions.copyImage(item) }
        Button("Save Image…", systemImage: "square.and.arrow.down") { actions.saveImage(item) }
        Divider()
        Button("Edit Tags…", systemImage: "tag") { actions.tagTargets = [item] }
        if item.isPrivate {
            Button("Remove from Private", systemImage: "lock.open") { actions.setPrivate(false, item) }
        } else {
            Button("Move to Private", systemImage: "lock") { actions.setPrivate(true, item) }
        }
        if item.isArchived {
            Button("Unarchive", systemImage: "tray.and.arrow.up") { actions.library.setArchived(false, [item]) }
        } else {
            Button("Archive", systemImage: "archivebox") { actions.library.setArchived(true, [item]) }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { actions.pendingDelete = [item] }
    }
}
