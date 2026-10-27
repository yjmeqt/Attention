import SwiftUI
import TipKit

/// Lives outside `HomeView` so scrolling only redraws the header glyph, not the feed.
@Observable
private final class HomeScroll {
    var scrolled = false
}

private struct HeaderGlyph: View {
    let scroll: HomeScroll

    var body: some View {
        AttentionGlyph(size: 30)
            .opacity(scroll.scrolled ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: scroll.scrolled)
            .accessibilityLabel(Brand.name)
            .accessibilityAddTraits(.isHeader)
    }
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
    @State private var guideWatched = false
    @State private var showsScanner = false
    @State private var showsLinkEntry = false
    @State private var typedLink = ""
    @State private var scroll = HomeScroll()
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    private let longPressTip = LongPressTip()
    @Namespace private var zoom
    @AppStorage("seenShareGuide") private var seenShareGuide = false
    @Environment(\.scenePhase) private var scenePhase

    init(library: Library) {
        self.library = library
        _actions = State(initialValue: ItemActions(library: library))
    }

    private var visible: [LibraryItem] { filter.apply(library.items) }
    /// While a site or tag filter is on, the bar stays so it can be changed or cleared.
    private var showsFilterBar: Bool {
        !library.items.isEmpty && (searching || !filter.domains.isEmpty || !filter.tags.isEmpty)
    }
    private var selectedItems: [LibraryItem] { library.items.filter { selection.contains($0.id) } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    if library.items.isEmpty {
                        EmptyState(showsPaste: false, paste: paste, onSample: openSample)
                            .frame(maxWidth: 520)
                            .padding(.horizontal)
                    } else {
                        feed
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
            // Right above the search field, which lives in the bottom bar.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsFilterBar {
                    FilterBar(filter: filter, items: library.items, library: library)
                        .padding(.bottom, 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: showsFilterBar)
            .scrollEdgeEffectHidden(true, for: .vertical)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columns = Waterfall<EmptyView>.columns(for: $0) }
            .onScrollGeometryChange(for: Bool.self) {
                $0.contentOffset.y + $0.contentInsets.top > 12
            } action: { [scroll] _, scrolled in
                scroll.scrolled = scrolled
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
            .searchable(text: $filter.search, isPresented: $searching, placement: .toolbar)
            .searchFocused($searchFocused)
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
                ShareSheetGuide(onWatched: { guideWatched = true })
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsGuide = false }
                                .disabled(!guideWatched)
                        }
                    }
            }
            .presentationSizing(.page)
            .interactiveDismissDisabled(!guideWatched)
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
            #if DEBUG
            await DemoLibrary.run(into: library)
            if DemoLibrary.unlocksPrivate {
                filter.showsPrivate = true
                // The first Face ID request after a boot can time out before its UI comes up; ask again.
                Task {
                    for _ in 0..<3 {
                        guard await DeviceOwner.authenticate(reason: String(localized: "Show your private items")) == .failed else { break }
                    }
                }
            }
            if let tag = DemoLibrary.tagFilter { filter.tags = [Library.normalizedTag(tag)] }
            if let text = DemoLibrary.search {
                searching = true
                filter.search = text
                // Results, not the keyboard, are what the screenshot shows.
                try? await Task.sleep(for: .seconds(1))
                searchFocused = false
            }
            if let index = DemoLibrary.open, library.items.indices.contains(index) { path = [library.items[index].id] }
            #endif
            Task { await library.retryMissingPreviews() }
            clipboardHasLink = await Clipboard.hasNewLink()
        }
        .onChange(of: library.items.count, initial: true) { _, count in LongPressTip.itemCount = count }
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
            if filter.isAll && filter.search.isEmpty {
                EmptyState(showsPaste: false, paste: paste, onSample: openSample)
                    .frame(maxWidth: 520)
                    .padding(.horizontal)
            } else if filter.search.isEmpty {
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
            .popoverTip(item.id == visible.first?.id ? longPressTip : nil, arrowEdge: .top)
            .contextMenu {
                ItemMenu(item: item, actions: actions, filter: filter) {
                    selecting = true
                    selection = [item.id]
                }
                .onAppear { longPressTip.invalidate(reason: .actionPerformed) }
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
                HeaderGlyph(scroll: scroll)
            }
            // Shown only while a section is open, so it's clear where you are and one tap gets you out.
            if filter.showsArchived {
                ToolbarItem(placement: .primaryAction) {
                    sectionButton("Archived", systemImage: "archivebox.fill", action: toggleArchived)
                }
            }
            if filter.showsPrivate {
                ToolbarItem(placement: .primaryAction) {
                    sectionButton("Private", systemImage: "lock.fill", action: togglePrivate)
                }
            }
            if filter.showsArchived || filter.showsPrivate {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
                    if !library.items.isEmpty {
                        Section {
                            Toggle(isOn: Binding(get: { filter.showsArchived }, set: { _ in toggleArchived() })) {
                                Label("Archived", systemImage: "archivebox")
                            }
                            Toggle(isOn: Binding(get: { filter.showsPrivate }, set: { _ in togglePrivate() })) {
                                Label("Private", systemImage: "lock")
                            }
                        }
                    }
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
            ToolbarItem(placement: .bottomBar) {
                // A plain button so it matches Scan; reading the clipboard asks the user each time.
                Button("Paste", systemImage: "clipboard") { paste(UIPasteboard.general.itemProviders) }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            // Unconditional: without it the system moves search up next to More.
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
        }
    }

    private func sectionButton(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .buttonStyle(.glassProminent)
            .tint(.accentColor)
            .accessibilityAddTraits(.isSelected)
    }

    private func toggleArchived() {
        if filter.showsArchived {
            filter.showsArchived = false
        } else {
            filter.clearFilters()
            filter.showsArchived = true
        }
    }

    private func togglePrivate() {
        if filter.showsPrivate { filter.reset() } else { unlockPrivate() }
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

    private func openSample(_ url: URL) { open(.link(url, image: nil)) }

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
