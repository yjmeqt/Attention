import SwiftUI

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
    @Environment(\.scenePhase) private var scenePhase

    init(library: Library) {
        self.library = library
        _actions = State(initialValue: ItemActions(library: library))
    }

    private var visible: [LibraryItem] { filter.apply(library.items) }
    private var selectedItems: [LibraryItem] { library.items.filter { selection.contains($0.id) } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    InputBar(clipboardHasLink: $clipboardHasLink, notice: $notice, submit: submit, paste: paste, scanned: scanned)
                        .frame(maxWidth: 600)
                        .padding(.horizontal)
                    if library.items.isEmpty {
                        EmptyState(showsPaste: !clipboardHasLink, paste: paste)
                            .frame(maxWidth: 520)
                            .padding(.horizontal)
                    } else {
                        FilterBar(filter: filter, items: library.items, onPrivate: unlockPrivate)
                        feed
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columns = Waterfall<EmptyView>.columns(for: $0) }
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $filter.search, placement: .navigationBarDrawer(displayMode: .automatic))
            .navigationTitle(Brand.name)
            .navigationDestination(for: UUID.self) { id in
                if let item = library.items.first(where: { $0.id == id }) {
                    ItemDetailView(item: item, library: library, privateUnlocked: filter.privateUnlocked)
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
                Task { clipboardHasLink = await Clipboard.hasNewLink() }
            } else if phase == .background {
                lockPrivate()
            }
        }
        .onChange(of: filter.showsPrivate) { _, shows in
            if !shows { lockPrivate() }
        }
        .task {
            HistoryImport.run(into: library)
            clipboardHasLink = await Clipboard.hasNewLink()
        }
        .onAppear {
            actions.onDeleted = { deleted in selection.subtract(deleted.map(\.id)) }
        }
    }

    @ViewBuilder
    private var feed: some View {
        if filter.showsPrivate && !filter.privateUnlocked {
            ContentUnavailableView("Private is locked", systemImage: "lock.fill")
        } else if visible.isEmpty {
            if filter.search.isEmpty {
                ContentUnavailableView(filter.showsPrivate ? "No private items" : "Nothing here", systemImage: "tray")
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
        let tile = FeedTile(item: item, library: library, isSelecting: selecting, isSelected: selection.contains(item.id))
        if selecting {
            Button {
                if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
            } label: { tile }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: item.id) { tile }
                .buttonStyle(.plain)
                .contextMenu {
                    ItemMenu(item: item, actions: actions, filter: filter) {
                        selecting = true
                        selection = [item.id]
                    }
                } preview: {
                    if let image = library.thumbnail(item) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(item.thumbnailAspect, contentMode: .fit)
                            .frame(width: 300)
                    }
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
                Button("Delete", systemImage: "trash", role: .destructive) { actions.delete(selectedItems) }
                    .disabled(selection.isEmpty)
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
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

private struct InputBar: View {
    @Binding var clipboardHasLink: Bool
    @Binding var notice: String?
    let submit: (String) -> Void
    let paste: ([NSItemProvider]) -> Void
    let scanned: (URL) -> Void

    @State private var input = ""
    @State private var showScanner = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            if clipboardHasLink {
                HStack {
                    Label("You copied a link", systemImage: "link")
                    Spacer()
                    PasteButton(supportedContentTypes: ItemProviders.pasteTypes, payloadAction: paste)
                }
                .padding(12)
                .background(.thinMaterial, in: .rect(cornerRadius: 12))
            }
            HStack {
                TextField("Paste a link", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($fieldFocused)
                    .onSubmit(go)
                    .onChange(of: input) { notice = nil }
                if !input.isEmpty {
                    Button("Go", systemImage: "arrow.right.circle.fill", action: go)
                        .labelStyle(.iconOnly)
                        .font(.title2)
                }
                PasteButton(supportedContentTypes: ItemProviders.pasteTypes, payloadAction: paste)
                    .labelStyle(.iconOnly)
                Button("Scan QR Code", systemImage: "qrcode.viewfinder") {
                    fieldFocused = false
                    showScanner = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
            }
            if let notice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showScanner) {
            QRScanSheet(onLink: scanned)
        }
    }

    private func go() {
        fieldFocused = false
        submit(input)
        if notice == nil { input = "" }
    }
}
