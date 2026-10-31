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
    @State private var guideFolded = 0
    @State private var showsScanner = false
    @State private var showsLinkEntry = false
    @State private var typedLink = ""
    @State private var scroll = HomeScroll()
    @State private var searching = false
    @State private var drawerOpen = false
    @State private var showsSettings = false
    @FocusState private var searchFocused: Bool
    private let longPressTip = LongPressTip()
    private let guideTip = GuideTip()
    @Namespace private var zoom
    @AppStorage("seenShareGuide") private var seenShareGuide = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(library: Library) {
        self.library = library
        _actions = State(initialValue: ItemActions(library: library))
    }

    private var visible: [LibraryItem] { filter.apply(library.items) }
    /// iPhone, and an iPad app in a narrow window: the sidebar is a drawer instead of a split view column.
    private var usesDrawer: Bool { sizeClass != .regular }
    private var selectedItems: [LibraryItem] { library.items.filter { selection.contains($0.id) } }

    var body: some View {
        Group {
            if usesDrawer {
                Drawer(isOpen: $drawerOpen, isEnabled: path.isEmpty && !selecting) {
                    sidebar
                } content: {
                    stack
                }
            } else {
                NavigationSplitView {
                    sidebar
                } detail: {
                    stack
                }
            }
        }
        .onChange(of: drawerOpen) { _, open in if open { searchFocused = false } }
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
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .sheet(isPresented: $showsGuide, onDismiss: guideDismissed) {
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
            // Dismissing shrinks the guide into More, where it can be replayed.
            .navigationTransition(.zoom(sourceID: Self.guideSource, in: zoom))
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
                filter.scope = .locked
                // The first Face ID request after a boot can time out before its UI comes up; ask again.
                // A matching face (simulator Face ID › Matching Face) opens Private, as the lock button does.
                Task {
                    for _ in 0..<3 {
                        let outcome = await DeviceOwner.authenticate(reason: String(localized: "Show your private items"))
                        if outcome == .authenticated {
                            filter.privateUnlocked = true
                            actions.privateUnlocked = true
                        }
                        guard outcome == .failed else { break }
                    }
                }
            }
            if let tag = DemoLibrary.tagFilter { filter.scope = .tag(Library.normalizedTag(tag)) }
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

    private var stack: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    // Inline, as a popover tip on the More menu never shows.
                    TipView(guideTip)
                        .frame(maxWidth: 520)
                        .padding(.horizontal)
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
                if clipboardHasLink && !selecting {
                    ClipboardBanner(paste: paste, dismiss: dismissClipboard)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 4)
                }
            }
            .animation(.snappy, value: clipboardHasLink)
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
            .navigationTitle(title)
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
    }

    private var sidebar: some View {
        Sidebar(library: library, filter: filter, select: select) {
            setDrawer(open: false)
            showsSettings = true
        }
    }

    private var title: String {
        switch filter.scope {
        case .all: Brand.name
        case .archived: String(localized: "Archived")
        case .locked: String(localized: "Private")
        case let .site(domain): DomainTag.label(domain)
        case let .tag(tag): "#\(tag)"
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
                ItemMenu(item: item, actions: actions)
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
            if usesDrawer {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Show Sidebar", systemImage: "line.3.horizontal") { setDrawer(open: true) }
                }
            }
            ToolbarItem(placement: .principal) {
                // All Items shows the glyph once scrolled; a site, tag, Archived or Private says which it is.
                if filter.isAll {
                    HeaderGlyph(scroll: scroll)
                } else {
                    Text(title).font(.headline).lineLimit(1)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Scan QR Code", systemImage: "qrcode.viewfinder") { showsScanner = true }
                    Button("Enter Link…", systemImage: "character.cursor.ibeam") { showsLinkEntry = true }
                    if !library.items.isEmpty {
                        Button("Select", systemImage: "checkmark.circle") { selecting = true }
                    }
                    NavigationLink {
                        ShareSheetGuide()
                            .onAppear { guideTip.invalidate(reason: .actionPerformed) }
                    } label: {
                        Label("Pin \(Brand.name) to the front of the share sheet", systemImage: "pin")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                        .symbolEffect(.bounce, value: guideFolded)
                }
                .sensoryFeedback(.impact(weight: .light), trigger: guideFolded)
            }
            .matchedTransitionSource(id: Self.guideSource, in: zoom)
            ToolbarItem(placement: .bottomBar) {
                // The system paste button reads the clipboard without the paste-permission prompt.
                PasteButton(supportedContentTypes: ItemProviders.pasteTypes, payloadAction: paste)
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            // Unconditional: without it the system moves search up next to More.
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
        }
    }

    private static let guideSource = "shareSheetGuide"

    /// Once the guide has shrunk into More, More bounces, then a tip says the guide lives there.
    private func guideDismissed() {
        seenShareGuide = true
        guideFolded += 1
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            GuideTip.guideFolded = true
        }
    }

    private func setDrawer(open: Bool) {
        withAnimation(.snappy(duration: 0.3)) { drawerOpen = open }
    }

    /// Leaving Private locks it again (see `onChange(of: filter.showsPrivate)`); entering it asks for Face ID first.
    private func select(_ scope: FeedFilter.Scope) {
        setDrawer(open: false)
        if scope == .locked {
            if !filter.showsPrivate { unlockPrivate() }
        } else {
            filter.scope = scope
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

    private func dismissClipboard() {
        Clipboard.ignoreCurrent()
        clipboardHasLink = false
    }

    private func scanned(_ url: URL) { open(.link(url, image: nil)) }

    private func openSample(_ url: URL) { open(.link(url, image: nil)) }

    private func open(_ capture: Capture) {
        notice = nil
        let item = library.save(capture)
        ShareSuggestion.save.donate()
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
            filter.scope = .locked
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

/// Offers a link the user copied elsewhere. Spotting it doesn't read the clipboard, and the system
/// paste button reads it without the paste-permission prompt.
private struct ClipboardBanner: View {
    let paste: ([NSItemProvider]) -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label("You copied a link", systemImage: "link")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            PasteButton(supportedContentTypes: ItemProviders.pasteTypes, payloadAction: paste)
                .buttonBorderShape(.capsule)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: 520)
        .padding(.horizontal)
    }
}
