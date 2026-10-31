import SwiftUI

/// The selected item: its card, what to do with it, and its style, tags and text.
struct ItemInspector: View {
    let item: LibraryItem
    let actions: LibraryActions

    @State private var image: NSImage?
    @State private var covers: (preview: NSImage?, shared: NSImage?, custom: NSImage?)?

    private var library: Library { actions.library }
    private var isLoading: Bool { library.enriching.contains(item.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                preview
                buttons
                details
                tags
                if let meta = library.meta(for: item) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let covers {
                            Text("Cover").font(.headline)
                            CoverPicker(preview: covers.preview, shared: covers.shared, custom: covers.custom, cover: coverBinding) {
                                library.setCustomImage($0, for: item)
                            } removeCustom: {
                                library.removeCustomImage(item)
                            }
                        }
                        Text("Template").font(.headline)
                        TemplatePicker(meta: meta, style: styleBinding)
                        if !isLoading { SourceImageInfo(meta: meta) }
                    }
                }
                if let text = item.ocrText, !text.isEmpty { recognizedText(text) }
            }
            .padding()
        }
        .task(id: "\(library.revision)-\(item.id)-\(item.templateRaw)-\(item.usesSharedImage)-\(item.usesCustomImage)") {
            image = library.fullImage(item)
            covers = item.isImage ? nil
                : (library.previewData(item).flatMap(Self.coverThumbnail),
                   library.data(.source, of: item).flatMap(Self.coverThumbnail),
                   library.data(.custom, of: item).flatMap(Self.coverThumbnail))
        }
    }

    private var preview: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 12))
                    .shadow(radius: 3)
                    .onDrag { actions.dragProvider(item) ?? NSItemProvider() }
                    .help("Drag into a chat, or copy it")
                    .accessibilityLabel(item.displayTitle)
            } else {
                RoundedRectangle(cornerRadius: 12).fill(.fill.tertiary).aspectRatio(0.8, contentMode: .fit)
            }
            if isLoading {
                ProgressView().padding(10).background(.regularMaterial, in: .circle)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var buttons: some View {
        HStack {
            Button("Copy Image", systemImage: "photo") { actions.copyImage(item) }
                .disabled(image == nil)
            if item.url != nil {
                Button("Copy Link", systemImage: "link") { actions.copyLink(item) }
            }
            Spacer()
            if let image {
                ShareLink(item: Image(nsImage: image), preview: SharePreview(item.displayTitle, image: Image(nsImage: image))) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .labelStyle(.iconOnly)
            }
            Menu("More", systemImage: "ellipsis") { ItemContextMenu(item: item, actions: actions) }
                .menuIndicator(.hidden)
                .labelStyle(.iconOnly)
                .fixedSize()
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !item.title.isEmpty {
                Text(item.title).font(.headline).textSelection(.enabled)
            }
            if let url = item.url {
                Link(destination: url) {
                    Label(LinkMeta(url: url, site: item.site, title: "").displayURL, systemImage: "link").lineLimit(1)
                }
                .font(.callout)
            }
            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var tags: some View {
        FlowLayout(spacing: 6) {
            chip(item.domainLabel, systemImage: item.isImage ? "photo" : "globe")
            if item.isPrivate { chip(String(localized: "Private"), systemImage: "lock.fill") }
            if item.isArchived { chip(String(localized: "Archived"), systemImage: "archivebox") }
            ForEach(item.tags, id: \.self) { chip("#\($0)", systemImage: nil) }
            Button("Edit Tags…", systemImage: "tag") { actions.tagTargets = [item] }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }

    private func chip(_ text: String, systemImage: String?) -> some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.fill.tertiary, in: .capsule)
    }

    private func recognizedText(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Text in Image").font(.headline)
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            Text(text).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .padding()
        .background(.fill.quinary, in: .rect(cornerRadius: 12))
    }

    private var coverBinding: Binding<Library.Cover> {
        Binding { library.cover(of: item) } set: { library.setCover($0, for: item) }
    }

    private var styleBinding: Binding<CardStyle> {
        Binding {
            item.style
        } set: { style in
            library.setStyle(style, for: item)
            style.save()
        }
    }

    private static func coverThumbnail(_ data: Data) -> NSImage? {
        ImageData.downsample(data, maxPixel: 300).map(NSImage.init(cgImage:))
    }
}

/// Lays chips out in rows, wrapping when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map { $0.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0 }.reduce(0, +)
            + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            let height = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for view in row {
                let size = view.sizeThatFits(.unspecified)
                view.place(at: CGPoint(x: x, y: y + (height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += height + spacing
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]]
        var x: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, !(rows.last?.isEmpty ?? true) {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(view)
            x += size.width + spacing
        }
        return rows
    }
}
