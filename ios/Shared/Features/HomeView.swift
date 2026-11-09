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
    @State private var detailID: UUID?
    @State private var notice: String?
    @State private var clipboardOffer: Clipboard.Offer?
    @State private var sampleLinkCopied = false
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
    @State private var visualScores: [UUID: Float] = [:]
    #if os(iOS) && !SHARE_EXTENSION
    @State private var assistant = Assistant()
    @State private var visualRequest = SearchRequest()
    #endif
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

    private var visible: [LibraryItem] {
        #if os(iOS) && !SHARE_EXTENSION
        filter.apply(library.items, visualScores: visualRequest.isCurrent(in: library, filter: filter) ? visualScores : [:], visualThreshold: ClipModel.matchThreshold)
        #else
        filter.apply(library.items)
        #endif
    }
    /// iPhone, and an iPad app in a narrow window: the sidebar is a drawer instead of a split view column.
    private var usesDrawer: Bool { sizeClass != .regular }
    private var selectedItems: [LibraryItem] { library.items.filter { selection.contains($0.id) } }

    var body: some View {
        Group {
            if usesDrawer {
                Drawer(isOpen: $drawerOpen, isEnabled: detailID == nil && !selecting) {
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
                Task { clipboardOffer = await Clipboard.newOffer() }
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
            #if DEBUG
            if !DemoLibrary.searchCorpus && !DemoLibrary.realLinks { HistoryImport.run(into: library) }
            #else
            HistoryImport.run(into: library)
            #endif
            #if DEBUG
            DemoLibrary.bulk(into: library)
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
            if let index = DemoLibrary.open, library.items.indices.contains(index) { detailID = library.items[index].id }
            #endif
            Task { await library.retryMissingPreviews() }
            clipboardOffer = await Clipboard.newOffer()
        }
        .onChange(of: library.items.count, initial: true) { _, count in LongPressTip.itemCount = count }
        #if os(iOS) && !SHARE_EXTENSION
        .onChange(of: filter.search) { _, _ in
            #if targetEnvironment(simulator)
            if !filter.search.isEmpty { Task { await assistant.verifyModelIfNeeded() } }
            #endif
        }
        .onChange(of: SearchContext(in: library, filter: filter)) { _, _ in assistant.reset() }
        .onChange(of: searching) { _, open in if !open { assistant.reset() } }
        .onDisappear { assistant.reset(); visualRequest.cancel() }
        .task(id: SearchContext(in: library, filter: filter)) { await refreshVisualScores() }
        #if targetEnvironment(simulator)
        .onChange(of: searching) { _, open in
            if open { Task { await assistant.verifyModelIfNeeded() } }
        }
        #endif
        .onChange(of: ClipModel.shared.isReady) { _, _ in
            Task {
                await library.embedPending()
                await refreshVisualScores()
            }
        }
        #endif
        .onAppear {
            actions.onDeleted = { deleted in selection.subtract(deleted.map(\.id)) }
            actions.onArchived = { archived in selection.subtract(archived.map(\.id)) }
        }
    }

    #if os(iOS) && !SHARE_EXTENSION
    private func refreshVisualScores() async {
        let token = visualRequest.begin(in: library, filter: filter)
        visualScores = [:]
        let query = filter.search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, ClipModel.shared.isReady else {
            visualScores = [:]
            return
        }
        let prompt = await ClipPrompt.english(for: query)
        guard visualRequest.accepts(token, in: library, filter: filter),
              let text = await ClipModel.shared.textEmbedding(prompt),
              visualRequest.accepts(token, in: library, filter: filter) else { return }
        var scores: [UUID: Float] = [:]
        for item in library.items {
            guard let image = library.embedding(of: item) else { continue }
            scores[item.id] = ClipModel.cosine(text, image)
        }
        visualScores = scores
    }
    #endif

    private var stack: some View {
        NavigationStack {
            feedContainer
            // Right above the search field, which lives in the bottom bar.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                #if os(iOS) && !SHARE_EXTENSION
                if searching && !selecting && (assistant.showsAskEntry || assistant.availabilityMessage != nil) {
                    VStack(alignment: .leading, spacing: 6) {
                        if assistant.showsAskEntry {
                            Button {
                                searchFocused = false
                                assistant.start(filter.search, in: library, scope: filter)
                            } label: {
                                Label("Ask", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!assistant.canAsk || assistant.isBusy || filter.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if let message = assistant.availabilityMessage {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                #endif
                if let clipboardOffer, !selecting {
                    ClipboardBanner(offer: clipboardOffer, paste: paste, dismiss: dismissClipboard)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 4)
                }
            }
            .animation(.snappy, value: clipboardOffer)
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
            // Selecting has no search. On a background, removing it doesn't rebuild the feed.
            .background {
                if !selecting {
                    Color.clear
                        .searchable(text: $filter.search, isPresented: $searching, placement: .toolbar)
                        .searchFocused($searchFocused)
                        .searchToolbarBehavior(.minimize)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .itemActionPresentations(actions)
            .onDrop(of: ItemProviders.pasteTypes, isTargeted: nil) { providers in
                paste(providers)
                return true
            }
        }
        .sheet(isPresented: Binding(get: { detailID != nil }, set: { if !$0 { detailID = nil } })) {
            if let detailID, let item = library.items.first(where: { $0.id == detailID }) {
                NavigationStack {
                    ItemDetailView(item: item, library: library, privateUnlocked: filter.privateUnlocked)
                }
                .presentationSizing(.page)
                .navigationTransition(.zoom(sourceID: detailID, in: zoom))
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

    /// Inline, as a popover tip on the More menu never shows.
    private var guideTipView: some View {
        TipView(guideTip)
            .frame(maxWidth: 520)
            .padding(.horizontal)
    }

    @ViewBuilder
    private var feedHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            guideTipView
            #if os(iOS) && !SHARE_EXTENSION
            if showingAsk {
                AskCard(assistant: assistant) {
                    assistant.start(filter.search, in: library, scope: filter)
                }
                .padding(.horizontal)
            }
            #endif
        }
    }

    @ViewBuilder
    private var feedContainer: some View {
        let items = askItems
        if !items.isEmpty, !(filter.showsPrivate && !filter.privateUnlocked) {
            let firstID = items.first?.id
            FeedCollection(items: items, columns: columns, tileRevision: tileRevision, onSelect: openTile) { [scroll] offset in
                let scrolled = offset > 12
                if scroll.scrolled != scrolled { scroll.scrolled = scrolled }
            } tile: { item, highlighted in
                tile(item, highlighted: highlighted, isFirst: item.id == firstID)
            } header: {
                feedHeader
            }
            .ignoresSafeArea(.container, edges: .vertical)
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    feedHeader
                    emptyFeed
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var tileRevision: Int {
        var hasher = Hasher()
        hasher.combine(selecting)
        hasher.combine(selection)
        #if os(iOS) && !SHARE_EXTENSION
        hasher.combine(String(describing: assistant.phase))
        hasher.combine(assistant.count)
        #endif
        return hasher.finalize()
    }

    private func openTile(_ item: LibraryItem) {
        if !selecting {
            detailID = item.id
        } else if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    private var showingAskDone: Bool {
        #if os(iOS) && !SHARE_EXTENSION
        showingAsk && assistant.phase == .done
        #else
        false
        #endif
    }

    private var showingAsk: Bool {
        #if os(iOS) && !SHARE_EXTENSION
        searching && assistant.isCurrent(in: library, scope: filter) && assistant.phase != .idle && assistant.phase != .unavailable && !assistant.modelFailed
        #else
        false
        #endif
    }

    private var askItems: [LibraryItem] {
        #if os(iOS) && !SHARE_EXTENSION
        if showingAsk && (assistant.phase == .matching || assistant.phase == .answering || assistant.phase == .done) {
            return assistant.matches.filter { library.contains($0) && filter.contains($0) }
        }
        #endif
        return visible
    }

    @ViewBuilder
    private func tile(_ item: LibraryItem, highlighted: Bool, isFirst: Bool) -> some View {
        Group {
            if selecting {
                FeedTile(item: item, library: library, isSelecting: true, isSelected: selection.contains(item.id))
            } else {
                FeedTile(item: item, library: library) { actions.openInApp(item) }
                    .matchedTransitionSource(id: item.id, in: zoom)
                    .popoverTip(isFirst ? longPressTip : nil, arrowEdge: .top)
                    .contextMenu {
                        ItemMenu(item: item, actions: actions)
                            .onAppear { longPressTip.invalidate(reason: .actionPerformed) }
                    } preview: {
                        FeedTile(item: item, library: library).frame(width: 280)
                    }
            }
        }
        .scaleEffect(highlighted ? 0.97 : 1)
        .animation(.spring(duration: 0.25), value: highlighted)
    }

    @ViewBuilder
    private var emptyFeed: some View {
        if filter.showsPrivate && !filter.privateUnlocked {
            ContentUnavailableView("Private is locked", systemImage: "lock.fill")
        } else if showingAskDone {
            ContentUnavailableView.search(text: filter.search)
        } else if showingAsk {
            EmptyView()
        } else if filter.isAll && filter.search.isEmpty {
            EmptyState(showsPaste: false, showsSampleLink: !sampleLinkCopied, paste: paste, onSample: copySample)
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
        clipboardOffer = nil
        Task {
            guard let capture = await Intake.capture(from: providers) else {
                notice = String(localized: "No link, image or text found on the clipboard.")
                return
            }
            open(capture)
        }
    }

    private func dismissClipboard() {
        Clipboard.ignoreCurrent()
        clipboardOffer = nil
    }

    private func scanned(_ url: URL) { open(.link(url, image: nil)) }

    private func copySample(_ url: URL) {
        Clipboard.copy(url, offerToPaste: true)
        sampleLinkCopied = true
        clipboardOffer = .link
    }

    private func open(_ capture: Capture) {
        notice = nil
        let item = library.save(capture)
        ShareSuggestion.save.donate()
        Task { await library.enrich(item) }
        if item.isPrivate && !filter.privateUnlocked {
            notice = String(localized: "Already saved in Private.")
            return
        }
        detailID = item.id
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
        #if os(iOS) && !SHARE_EXTENSION
        assistant.reset()
        visualRequest.cancel()
        visualScores = [:]
        #endif
        let wasShowingPrivate = filter.showsPrivate
        filter.privateUnlocked = false
        actions.privateUnlocked = false
        if wasShowingPrivate { filter.reset() }
        let privateIDs = Set(library.items.filter(\.isPrivate).map(\.id))
        if let detailID, privateIDs.contains(detailID) { self.detailID = nil }
        selection.subtract(privateIDs)
    }
}

/// Offers a link, image or text the user copied elsewhere. Spotting it doesn't read the clipboard, and the system
/// paste button reads it without the paste-permission prompt.
private struct ClipboardBanner: View {
    let offer: Clipboard.Offer
    let paste: ([NSItemProvider]) -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch offer {
                case .link: Label("You copied a link", systemImage: "link")
                case .text: Label("Text copied", systemImage: "text.alignleft")
                case .image: Label("Image copied", systemImage: "photo")
                }
            }
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
