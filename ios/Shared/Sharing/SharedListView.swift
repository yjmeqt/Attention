import SwiftUI

/// A list someone shared, opened from its universal link: the whole list, read-only,
/// with a button that saves it into the library under the list's title.
struct SharedListView: View {
    let link: SharedListLink
    let library: Library

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var state: LoadState = .loading
    @State private var savedCount: Int?

    enum LoadState: Equatable {
        case loading
        case loaded(SharedList)
        case failed(SharedListError)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .task(id: link) { await load() }
    }

    private var navigationTitle: String {
        if case .loaded(let list) = state { return list.title }
        return String(localized: "Shared List")
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView("Loading the list…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            failure(error)
        case .loaded(let list):
            loaded(list)
        }
    }

    private func loaded(_ list: SharedList) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(list.items.count) items · Shared \(list.createdAt, format: .dateTime.year().month().day())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                SharedWaterfall(items: list.items, columns: horizontalSizeClass == .regular ? 3 : 2) { item in
                    SharedTile(item: item) { item.url.map { openURL($0) } }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .safeAreaInset(edge: .bottom) {
            saveBar(list)
        }
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private func saveBar(_ list: SharedList) -> some View {
        VStack(spacing: 6) {
            if let savedCount {
                Label("Saved \(savedCount) items, tagged “\(Library.normalizedTag(list.title))”", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.vertical, 12)
            } else {
                Button {
                    let saved = library.save(list)
                    savedCount = saved.count
                    Task { await library.retryMissingPreviews() }
                } label: {
                    Text("Save to My Library")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Text("Saved items are tagged with the list's title.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(.bar)
    }

    private func failure(_ error: SharedListError) -> some View {
        ContentUnavailableView {
            switch error {
            case .gone: Label("This List Was Taken Down", systemImage: "eye.slash")
            case .notFound: Label("List Not Found", systemImage: "questionmark.folder")
            case .unavailable: Label("Couldn't Load the List", systemImage: "wifi.exclamationmark")
            }
        } description: {
            switch error {
            case .gone: Text("The person who shared it revoked it, or it was removed after a report.")
            case .notFound: Text("The link may be incomplete. Check with the person who shared it.")
            case .unavailable: Text("Check your connection and try again.")
            }
        } actions: {
            if error == .unavailable {
                Button("Try Again") { Task { await load() } }
            }
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await SharedListClient.fetch(link))
        } catch {
            state = .failed(error)
        }
    }
}

/// The feed's staggered grid (`Waterfall`) for a shared list: each tile goes to the shorter column.
struct SharedWaterfall<Content: View>: View {
    let items: [SharedList.Item]
    let columns: Int
    var spacing: CGFloat = 12
    @ViewBuilder let content: (SharedList.Item) -> Content

    var body: some View {
        let lanes = Self.lanes(for: items, columns: columns)
        HStack(alignment: .top, spacing: spacing) {
            ForEach(lanes.indices, id: \.self) { index in
                LazyVStack(spacing: spacing) {
                    ForEach(lanes[index]) { content($0) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    /// Heights are estimated like the feed's: a photo by its aspect ratio, text by its length.
    static func lanes(for items: [SharedList.Item], columns: Int) -> [[SharedList.Item]] {
        let count = max(columns, 1)
        var lanes = Array(repeating: [SharedList.Item](), count: count)
        var heights = Array(repeating: 0.0, count: count)
        for item in items {
            let lane = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            lanes[lane].append(item)
            let photo = item.thumb != nil ? 1 / max(item.aspect ?? 1.33, 0.25) : 0
            let text = Double(min((item.text ?? item.title ?? "").count, 160)) / 160 * 0.6
            heights[lane] += photo + text + 0.35
        }
        return lanes
    }
}

/// A feed tile for an item of a shared list: like `FeedTile`, with the server's thumbnail.
struct SharedTile: View {
    let item: SharedList.Item
    var onOpen: () -> Void

    @State private var photo: PlatformImage?

    var body: some View {
        FeedTileFace(photo: photo, aspect: max(item.aspect ?? photo.map { Double($0.size.width / max($0.size.height, 1)) } ?? 1, 0.5),
                     tint: photo.flatMap { CardTint($0) }, title: title,
                     lockupLines: item.kind == .text ? 8 : 6, fillsCell: false) {
            eyebrow
        } footer: {
            if item.kind == .link {
                HStack {
                    if let author = item.author {
                        Text(verbatim: author).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button("Open", action: onOpen)
                        .font(.caption.weight(.bold))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                }
            }
        }
        .contentShape(.rect(cornerRadius: 16, style: .continuous))
        .onTapGesture { if item.kind == .link { onOpen() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(item.kind == .link ? .isButton : [])
        .task(id: item.thumb) { photo = await Self.load(item.thumb) }
    }

    private var title: String {
        if item.kind == .text { return item.text ?? "" }
        if let title = item.title, !title.isEmpty { return title }
        return item.url?.host() ?? item.url?.absoluteString ?? ""
    }

    private var eyebrow: some View {
        HStack(spacing: 4) {
            Image(systemName: item.kind == .text ? "text.alignleft" : "globe")
            Text(verbatim: item.kind == .text ? String(localized: "Text") : (item.site?.isEmpty == false ? item.site! : item.url?.host() ?? ""))
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private static func load(_ url: URL?) async -> PlatformImage? {
        guard let url, let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return PlatformImage(data: data)
    }
}

/// Opens shared-list links, from a tap in Safari, a scanned QR code or the web page's button, in a sheet.
struct SharedListOpener: ViewModifier {
    let library: Library
    @State private var link: SharedListLink?

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                if let shared = SharedListLink(url: url) { link = shared }
            }
            #if DEBUG
            // Simulators don't hand universal links to apps reliably; `-openSharedList <url>` stands in for one.
            .task {
                if let string = UserDefaults.standard.string(forKey: "openSharedList"),
                   let url = URL(string: string), let shared = SharedListLink(url: url) { link = shared }
            }
            #endif
            .environment(\.feedIsCovered, link != nil)
            .sheet(item: $link) { link in
                SharedListView(link: link, library: library)
            }
    }
}
