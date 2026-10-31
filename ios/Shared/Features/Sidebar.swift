import SwiftUI

/// All items, then sites and tags of the live items; Archived, Private and Settings stay pinned at the bottom.
/// The drawer on iPhone and the split view's sidebar on iPad both show it.
struct Sidebar: View {
    let library: Library
    let filter: FeedFilter
    let select: (FeedFilter.Scope) -> Void
    let openSettings: () -> Void

    @State private var showsSites = true
    @State private var showsTags = true
    @State private var allSites = false
    @State private var allTags = false

    /// Sites and tags past this many hide behind Show All.
    private static let shortList = 5

    var body: some View {
        let live = library.items.filter(FeedFilter.isLive)
        let sites = FeedFilter.counted(live.map(\.domain))
        let tags = FeedFilter.counted(live.flatMap(\.tags))
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 10) {
                        AttentionGlyph(size: 28)
                        Text(Brand.name).font(.title3.bold())
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    row(.all, count: live.count) {
                        Label("All Items", systemImage: "square.grid.2x2")
                    }

                    if !sites.isEmpty {
                        header("Sites", expanded: $showsSites)
                        if showsSites {
                            ForEach(allSites ? sites : Array(sites.prefix(Self.shortList)), id: \.value) { site in
                                row(.site(site.value), count: site.count) {
                                    Label { Text(DomainTag.label(site.value)) } icon: { siteIcon(site.value, in: live) }
                                }
                            }
                            if sites.count > Self.shortList { moreButton($allSites) }
                        }
                    }

                    if !tags.isEmpty {
                        header("Tags", expanded: $showsTags)
                        if showsTags {
                            ForEach(allTags ? tags : Array(tags.prefix(Self.shortList)), id: \.value) { tag in
                                row(.tag(tag.value), count: tag.count) {
                                    Label(tag.value, systemImage: "number")
                                }
                            }
                            if tags.count > Self.shortList { moreButton($allTags) }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            VStack(alignment: .leading, spacing: 2) {
                Divider().padding(.horizontal, 12).padding(.bottom, 6)
                row(.archived) { Label("Archived", systemImage: "archivebox") }
                row(.locked) { Label("Private", systemImage: filter.privateUnlocked ? "lock.open" : "lock") }
                rowButton(selected: false, action: openSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private func row(_ scope: FeedFilter.Scope, count: Int? = nil, @ViewBuilder label: () -> some View) -> some View {
        rowButton(selected: filter.scope == scope, count: count) { select(scope) } label: { label() }
    }

    private func rowButton(selected: Bool, count: Int? = nil, action: @escaping () -> Void,
                           @ViewBuilder label: () -> some View) -> some View {
        Button(action: action) {
            HStack {
                label()
                    .labelStyle(SidebarLabelStyle())
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let count {
                    Text(count, format: .number)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .fontWeight(selected ? .semibold : .regular)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(selected ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 12, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func header(_ title: LocalizedStringKey, expanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.snappy) { expanded.wrappedValue.toggle() }
        } label: {
            HStack {
                Text(title)
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .rotationEffect(.degrees(expanded.wrappedValue ? 90 : 0))
                Spacer()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 18)
            .padding(.bottom, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(expanded.wrappedValue ? Text("Expanded") : Text("Collapsed"))
    }

    private func moreButton(_ showsAll: Binding<Bool>) -> some View {
        Button(showsAll.wrappedValue ? "Show Less" : "Show All") {
            withAnimation(.snappy) { showsAll.wrappedValue.toggle() }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func siteIcon(_ domain: String, in items: [LibraryItem]) -> some View {
        if let item = items.first(where: { $0.domain == domain }), let icon = library.favicon(item) {
            Image(uiImage: icon).resizable().scaledToFit()
                .frame(width: 18, height: 18)
                .clipShape(.rect(cornerRadius: 4, style: .continuous))
        } else {
            Image(systemName: domain == DomainTag.images ? "photo" : "globe")
        }
    }
}

/// Icons in one column whatever their glyph's width.
private struct SidebarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .foregroundStyle(.secondary)
                .frame(width: 24)
            configuration.title
        }
    }
}
