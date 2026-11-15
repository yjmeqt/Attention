import SwiftUI

/// Shared Lists, from the sidebar: one card per list this person shared, showing the picture people see
/// when the link unfurls, with its title and actions. Tapping a card opens the list as a feed.
struct SharedListsView: View {
    let library: Library

    @State private var records: [SharedListRecord] = []
    @State private var actions = SharedListActions()

    var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView {
                    Label("No Shared Lists", systemImage: "square.and.arrow.up.on.square")
                } description: {
                    Text("To share a list, choose Select in More, pick the items and tap Share as List. You can also touch and hold a tag in the sidebar.")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(records) { record in
                            card(record)
                        }
                        Text("Anyone with a list's link can see it until you take it down. Taking a list down deletes it from Attention's server.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    .frame(maxWidth: 480)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Shared Lists")
        .modifier(SharedListActionsModifier(actions: actions, library: library, onTakenDown: { _ in reload() }))
        .onAppear(perform: reload)
    }

    private func card(_ record: SharedListRecord) -> some View {
        NavigationLink {
            SharedListDetailView(record: record, library: library, onTakenDown: reload)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                SharedListPreviewImage(record: record)
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: record.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text("\(record.itemCount) items · Shared \(record.createdAt, format: .dateTime.year().month().day())")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    // Room for the menu, which sits over the card rather than inside the link.
                    Color.clear.frame(width: 32, height: 32)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondaryBackground)
            }
            .clipShape(.rect(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.separator.opacity(0.4), lineWidth: 0.5)
            }
            .contentShape(.rect(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            SharedListMenu(record: record, actions: actions)
                .padding(14)
        }
        .disabled(actions.working.contains(record.listID))
    }

    private func reload() {
        records = library.sharedLists()
    }
}

/// A shared list's own link preview, as `og.jpg` from the server; lists shared without one get a plain square.
struct SharedListPreviewImage: View {
    let record: SharedListRecord

    var body: some View {
        Color.secondaryBackground
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AsyncImage(url: record.url.appending(path: "og.jpg")) { phase in
                    if let image = phase.image {
                        // Square now; lists shared before were 16:9, so fit rather than crop.
                        image.resizable().scaledToFit()
                    } else if phase.error != nil {
                        Image(systemName: "square.and.arrow.up.on.square")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// Share, copy or take down a shared list, from its card or its page.
struct SharedListMenu: View {
    let record: SharedListRecord
    let actions: SharedListActions

    var body: some View {
        Menu {
            Button("Share Link", systemImage: "square.and.arrow.up") { actions.share(record) }
            Button("Copy Link", systemImage: "link") { Clipboard.copy(record.url) }
            Button("Take Down…", systemImage: "trash", role: .destructive) { actions.pendingTakeDown = record }
        } label: {
            Group {
                if actions.working.contains(record.listID) {
                    ProgressView()
                } else {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                }
            }
            .frame(width: 32, height: 32)
            .background(.fill.tertiary, in: .circle)
            .contentShape(.circle)
        }
        .tint(.primary)
        .accessibilityLabel(Text("More"))
    }
}

/// What both pages do with a shared list: share its link, and take it down after asking.
@Observable
final class SharedListActions {
    var pendingTakeDown: SharedListRecord?
    var working: Set<String> = []
    var message: String?
    @ObservationIgnored let presenter = SharePresenter()

    func share(_ record: SharedListRecord) {
        presenter.present([ShareItem(url: record.url, title: record.title, icon: nil)])
    }

    /// True when the list is gone from the server and its record removed.
    func takeDown(_ record: SharedListRecord, library: Library) async -> Bool {
        let id = record.listID
        working.insert(id)
        defer { working.remove(id) }
        do {
            try await ListSharingClient.revoke(id: id, token: record.deleteToken)
            library.removeSharedList(id: id)
            return true
        } catch .rejected {
            message = String(localized: "Attention's server didn't accept the request to take this list down.")
        } catch {
            message = String(localized: "Couldn't reach Attention's server. Check your connection and try again.")
        }
        return false
    }
}

/// The take-down confirmation, the error alert and the share sheet's anchor for `SharedListActions`.
struct SharedListActionsModifier: ViewModifier {
    @Bindable var actions: SharedListActions
    let library: Library
    let onTakenDown: (SharedListRecord) -> Void

    func body(content: Content) -> some View {
        content
            .background { ShareAnchor(presenter: actions.presenter) }
            .confirmationDialog("Take down “\(actions.pendingTakeDown?.title ?? "")”?",
                                isPresented: Binding(get: { actions.pendingTakeDown != nil },
                                                     set: { if !$0 { actions.pendingTakeDown = nil } }),
                                titleVisibility: .visible, presenting: actions.pendingTakeDown) { record in
                Button("Take Down", role: .destructive) {
                    Task {
                        if await actions.takeDown(record, library: library) { onTakenDown(record) }
                    }
                }
            } message: { _ in
                Text("The link stops working for everyone. People who already saved its items keep them.")
            }
            .alert("Shared Lists", isPresented: Binding(get: { actions.message != nil }, set: { if !$0 { actions.message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actions.message ?? "")
            }
    }
}

/// One shared list, as the people it was sent to see it in Attention: its items as a feed.
struct SharedListDetailView: View {
    let record: SharedListRecord
    let library: Library
    let onTakenDown: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var state: SharedListView.LoadState = .loading
    @State private var actions = SharedListActions()

    var body: some View {
        content
            .navigationTitle(Text(verbatim: record.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Share Link", systemImage: "square.and.arrow.up") { actions.share(record) }
                }
                ToolbarItem(placement: .primaryAction) {
                    SharedListMenu(record: record, actions: actions)
                }
            }
            .modifier(SharedListActionsModifier(actions: actions, library: library, onTakenDown: { _ in
                onTakenDown()
                dismiss()
            }))
            .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView("Loading the list…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(.gone):
            ContentUnavailableView("This List Was Taken Down", systemImage: "eye.slash",
                                   description: Text("The person who shared it revoked it, or it was removed after a report."))
        case .failed:
            ContentUnavailableView {
                Label("Couldn't Load the List", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        case .loaded(let list):
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(list.items.count) items · Shared \(list.createdAt, format: .dateTime.year().month().day())")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(verbatim: list.url.absoluteString)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    SharedWaterfall(items: list.items, columns: horizontalSizeClass == .regular ? 3 : 2) { item in
                        SharedTile(item: item) { item.url.map { openURL($0) } }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private func load() async {
        guard let link = SharedListLink(url: record.url) else { return }
        state = .loading
        do {
            state = .loaded(try await SharedListClient.fetch(link))
        } catch {
            state = .failed(error)
            // Taken down elsewhere, or after a report: there's nothing left to manage.
            if error == .gone { library.removeSharedList(id: record.listID) }
        }
    }
}
