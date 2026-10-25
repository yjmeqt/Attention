import SwiftUI

private struct ScrollPosition: Equatable {
    var offset: CGFloat
    var inset: CGFloat
}

struct HomeView: View {
    let library: Library

    @State private var filter = FeedFilter()
    @State private var actions: ItemActions
    @State private var path: [UUID] = []
    @State private var notice: String?
    @State private var clipboardHasLink = false
    @State private var columns = 2
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var showsGuide = false
    @State private var showsScanner = false
    @State private var showsLinkEntry = false
    @State private var typedLink = ""
    /// The filter bar hides while scrolling into the feed and comes back on a downward swipe.
    @State private var showsFilters = false
    @State private var scrolled = false
    @Namespace private var zoom
    @AppStorage("seenShareGuide") private var seenShareGuide = false
    @Environment(\.scenePhase) private var scenePhase

    init(library: Library) {
        self.library = library
        _actions = State(initialValue: ItemActions(library: library))
    }

    private var visible: [LibraryItem] { filter.apply(library.items) }
    private var filterBarShown: Bool { !library.items.isEmpty && (showsFilters || !filter.isAll) }
    private var selectedItems: [LibraryItem] { library.items.filter { selection.contains($0.id) } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    if library.items.isEmpty {
                        EmptyState(showsPaste: false, paste: paste)
                            .frame(maxWidth: 520)
                            .padding(.horizontal)
                    } else {
                        feed
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columns = Waterfall<EmptyView>.columns(for: $0) }
            .onScrollGeometryChange(for: ScrollPosition.self) {
                ScrollPosition(offset: $0.contentOffset.y + $0.contentInsets.top, inset: $0.contentInsets.top)
            } action: { oldPosition, position in                // Showing or hiding the filter bar changes the inset; that isn't the user scrolling.
                guard oldPosition.inset == position.inset else { return }
                let old = oldPosition.offset, new = position.offset
                scrolled = new > 12
                let delta = new - old
                withAnimation(.snappy) {
                    if new < -24 || (delta < -6 && new > 0) {
                        showsFilters = true
                    } else if delta > 6 && new > 0 {
                        showsFilters = false
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if filterBarShown {
                    FilterBar(filter: filter, items: library.items, onPrivate: unlockPrivate)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottom) {
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: notice) {
                            try? await Task.sleep(for: .seconds(3))
                            withAnimation { self.notice = nil }
                        }
                }
            }
            .animation(.snappy, value: notice)
            .searchable(text: $filter.search, placement: .toolbar)
            .searchToolbarBehavior(.minimize)
            .navigationTitle(Brand.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                if let item = library.items.first(where: { $0.id == id }) {
                    ItemDetailView(item: item, library: library, privateUnlocked: filter.privateUnlocked)
                        .navigationTransition(.zoom(sourceID: id, in: zoom))
                }
            }
            .toolbar { toolbar }
            .itemActionPresentations(actions)
            .onDrop(of: ItemProviders.pasteTypes, isTargeted: nil) { providers in
                paste(providers)
                return true
            }
        }
        .overlay {
            if filter.showsPrivate, scenePhase != .active {
                Rectangle().fill(.regularMaterial).ignoresSafeArea()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                library.reload()
                Task { await library.retryMissingPreviews() }
                Task { clipboardHasLink = await Clipboard.hasNewLink() }
            } else if phase == .background {
                lockPrivate()
            }
        }
        .onChange(of: filter.showsPrivate) { _, shows in
            if !shows { lockPrivate() }
        }
        .sheet(isPresented: $showsGuide, onDismiss: { seenShareGuide = true }) {
            NavigationStack {
                ShareSheetGuide()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsGuide = false }
                        }
                    }
            }
            .presentationSizing(.page)
        }
        .sheet(isPresented: $showsScanner) {
            QRScanSheet(onLink: scanned)
        }
        .alert("Enter Link", isPresented: $showsLinkEntry) {
            TextField("https://", text: $typedLink)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { typedLink = "" }
            Button("Go") {
                submit(typedLink)
                typedLink = ""
            }
        }
        .task {
            if !seenShareGuide { showsGuide = true }
            HistoryImport.run(into: library)
            Task { await library.retryMissingPreviews() }
            clipboardHasLink = await Clipboard.hasNewLink()
        }
        .onAppear {
            actions.onDeleted = { deleted in selection.subtract(deleted.map(\.id)) }
            actions.onArchived = { archived in selection.subtract(archived.map(\.id)) }
        }
    }

    @ViewBuilder
    private var feed: some View {
        if filter.showsPrivate && !filter.privateUnlocked {
            ContentUnavailableView("Private is locked", systemImage: "lock.fill")
        } else if visible.isEmpty {
            if filter.search.isEmpty {
                ContentUnavailableView(
                    filter.showsArchived ? "No archived items" : filter.showsPrivate ? "No private items" : "Nothing here",
                    systemImage: filter.showsArchived ? "archivebox" : "tray"
                )
            } else {
                ContentUnavailableView.search(text: filter.search)
            }
        } else {
            Waterfall(items: visible, columns: columns) { item in
                tile(item)
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func tile(_ item: LibraryItem) -> some View {
        if selecting {
            Button {
                if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
            } label: {
                FeedTile(item: item, library: library, isSelecting: true, isSelected: selection.contains(item.id))
            }
            .buttonStyle(PressableStyle())
        } else {
            NavigationLink(value: item.id) {
                FeedTile(item: item, library: library) { actions.openInApp(item) }
            }
            .buttonStyle(PressableStyle())
            .matchedTransitionSource(id: item.id, in: zoom)
            .contextMenu {
                ItemMenu(item: item, actions: actions, filter: filter) {
                    selecting = true
                    selection = [item.id]
                }
            } preview: {
                FeedTile(item: item, library: library).frame(width: 280)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if selecting {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    selecting = false
                    selection = []
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Tag", systemImage: "tag") { actions.editTags(selectedItems) }
                    .disabled(selection.isEmpty)
                Spacer()
                if filter.showsPrivate {
                    Button("Remove from Private", systemImage: "lock.open") { Task { await actions.setPrivate(false, selectedItems) } }
                        .disabled(selection.isEmpty)
                } else {
                    Button("Move to Private", systemImage: "lock") { Task { await actions.setPrivate(true, selectedItems) } }
                        .disabled(selection.isEmpty)
                }
                Spacer()
                if filter.showsArchived {
                    Button("Unarchive", systemImage: "tray.and.arrow.up") { actions.setArchived(false, selectedItems) }
                        .disabled(selection.isEmpty)
                } else {
                    Button("Archive", systemImage: "archivebox") { actions.setArchived(true, selectedItems) }
                        .disabled(selection.isEmpty)
                }
                Spacer()
                Button("Delete", systemImage: "trash", role: .destructive) { actions.delete(selectedItems) }
                    .disabled(selection.isEmpty)
            }
        } else {
            ToolbarItem(placement: .principal) {
                OpticShareGlyph(size: 30)
                    .opacity(scrolled ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: scrolled)
                    .accessibilityLabel(Brand.name)
                    .accessibilityAddTraits(.isHeader)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Enter Link…", systemImage: "character.cursor.ibeam") { showsLinkEntry = true }
                    if !library.items.isEmpty {
                        Button("Select", systemImage: "checkmark.circle") { selecting = true }
                    }
                    NavigationLink {
                        ShareSheetGuide()
                    } label: {
                        Label("Pin \(Brand.name) to the front of the share sheet", systemImage: "pin")
                    }
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Scan QR Code", systemImage: "qrcode.viewfinder") { showsScanner = true }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                PasteButton(supportedContentTypes: ItemProviders.pasteTypes, payloadAction: paste)
                    .labelStyle(.titleAndIcon)
                    .tint(.accentColor)
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            if !library.items.isEmpty {
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
        }
    }

    // MARK: - Intake

    private func submit(_ text: String) {
        guard let url = URL.extract(from: text) else {
            notice = String(localized: "No link found in that text.")
            return
        }
        open(.link(url, image: nil))
    }

    private func paste(_ providers: [NSItemProvider]) {
        Clipboard.ignoreCurrent()
        clipboardHasLink = false
        Task {
            guard let capture = await Intake.capture(from: providers) else {
                notice = String(localized: "No link found on the clipboard.")
                return
            }
            open(capture)
        }
    }

    private func scanned(_ url: URL) { open(.link(url, image: nil)) }

    private func open(_ capture: Capture) {
        notice = nil
        let item = library.save(capture)
        Task { await library.enrich(item) }
        if item.isPrivate && !filter.privateUnlocked {
            notice = String(localized: "Already saved in Private.")
            return
        }
        path = [item.id]
    }

    // MARK: - Private

    private func unlockPrivate() {
        Task {
            switch await DeviceOwner.authenticate(reason: String(localized: "Show your private items")) {
            case .authenticated: break
            case .failed: return
            case .unavailable:
                actions.showsPasscodeRequired = true
                return
            }
            selecting = false
            selection = []
            filter.reset()
            filter.showsPrivate = true
            filter.privateUnlocked = true
            actions.privateUnlocked = true
        }
    }

    private func lockPrivate() {
        let wasShowingPrivate = filter.showsPrivate
        filter.privateUnlocked = false
        actions.privateUnlocked = false
        if wasShowingPrivate { filter.reset() }
        let privateIDs = Set(library.items.filter(\.isPrivate).map(\.id))
        if path.contains(where: privateIDs.contains) { path = [] }
        selection.subtract(privateIDs)
    }
}
