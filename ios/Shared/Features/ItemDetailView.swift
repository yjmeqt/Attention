import SwiftUI

/// A saved item: its card (or image), style, tags and actions. Used by the app and the share extension.
struct ItemDetailView: View {
    let item: LibraryItem
    /// Set in the share extension: shows a Done button that closes it.
    var onDone: (() -> Void)?
    /// Opens the share sheet with the card as soon as the view is up, for Sherlock's suggestion.
    var autoShare = false

    @State private var actions: ItemActions
    @State private var image: UIImage?
    /// The link's preview image and the image it was shared as, when they differ.
    @State private var covers: (preview: UIImage?, shared: UIImage?)?
    @Environment(\.dismiss) private var dismiss

    init(item: LibraryItem, library: Library, privateUnlocked: Bool = false, autoShare: Bool = false, onDone: (() -> Void)? = nil) {
        self.item = item
        self.onDone = onDone
        self.autoShare = autoShare
        let actions = ItemActions(library: library)
        actions.privateUnlocked = privateUnlocked
        _actions = State(initialValue: actions)
    }

    private var library: Library { actions.library }
    private var isLoading: Bool { library.enriching.contains(item.id) }

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width > proxy.size.height && proxy.size.width > 700
            ScrollView {
                if isWide {
                    HStack(alignment: .top, spacing: 32) {
                        preview(maxHeight: proxy.size.height - 160)
                        details.frame(maxWidth: 420)
                    }
                    .padding()
                } else {
                    VStack(spacing: 20) {
                        preview(maxHeight: proxy.size.height * 0.62)
                        details
                    }
                    .frame(maxWidth: 520)
                    .padding()
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(item.isImage ? String(localized: "Image") : item.domainLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .safeAreaBar(edge: .bottom) { bottomBar }
        .itemActionPresentations(actions)
        .task(id: "\(library.revision)-\(item.templateRaw)") {
            image = library.fullImage(item)
            covers = library.hasCoverChoice(item)
                ? (library.data(.cover, of: item).flatMap(Self.coverThumbnail),
                   library.data(.source, of: item).flatMap(Self.coverThumbnail))
                : nil
        }
        .task {
            guard autoShare else { return }
            // The share anchor needs to be in the window before the sheet can present from it.
            try? await Task.sleep(for: .milliseconds(400))
            actions.shareImage(item)
        }
        .onAppear {
            actions.copied = nil
            actions.onDeleted = { deleted in
                guard deleted.contains(where: { $0.id == item.id }) else { return }
                if let onDone { onDone() } else { dismiss() }
            }
        }
    }

    private func preview(maxHeight: CGFloat) -> some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 16))
                    .shadow(radius: 4)
                    .accessibilityLabel(item.displayTitle)
                    .accessibilityIdentifier("CardPreview")
            } else {
                RoundedRectangle(cornerRadius: 16).fill(.fill.tertiary)
                    .aspectRatio(0.8, contentMode: .fit)
            }
            if isLoading {
                ProgressView()
                    .padding(12)
                    .background(.regularMaterial, in: .circle)
            }
        }
        .frame(maxHeight: max(maxHeight, 240))
        .frame(maxWidth: .infinity)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                if !item.title.isEmpty {
                    Text(item.title).font(.headline).textSelection(.enabled)
                }
                if let url = item.url {
                    Button {
                        actions.openInBrowser(item)
                    } label: {
                        Label(LinkMeta(url: url, site: item.site, title: "").displayURL, systemImage: "link")
                            .lineLimit(1)
                    }
                    .font(.footnote)
                }
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TagRow(item: item, actions: actions)

            if let meta = library.meta(for: item) {
                VStack(alignment: .leading, spacing: 12) {
                    if let covers {
                        Text("Cover").font(.headline)
                        CoverPicker(preview: covers.preview, shared: covers.shared, usesShared: sharedImageBinding)
                    }
                    Text("Template").font(.headline)
                    TemplatePicker(meta: meta, style: styleBinding)
                    if !isLoading { SourceImageInfo(meta: meta) }
                }
            }

            if let text = item.ocrText, !text.isEmpty {
                RecognizedText(text: text)
            }
        }
    }

    private var sharedImageBinding: Binding<Bool> {
        Binding { item.usesSharedImage } set: { library.setUsesSharedImage($0, for: item) }
    }

    private static func coverThumbnail(_ data: Data) -> UIImage? {
        ImageData.downsample(data, maxPixel: 300).map(UIImage.init(cgImage:))
    }

    private var styleBinding: Binding<CardStyle> {
        Binding {
            item.style
        } set: { style in
            library.setStyle(style, for: item)
            style.save()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu("More", systemImage: "ellipsis") {
                if item.url != nil {
                    if Opening.canOpenApps {
                        Button("Open in App", systemImage: "arrow.up.forward.app") { actions.openInApp(item) }
                    }
                    Button("Open in Browser", systemImage: "safari") { actions.openInBrowser(item) }
                }
                Button("Edit Tags…", systemImage: "tag") { actions.editTags([item]) }
                if item.isPrivate {
                    Button("Remove from Private", systemImage: "lock.open") { Task { await actions.setPrivate(false, [item]) } }
                } else {
                    Button("Move to Private", systemImage: "lock") { Task { await actions.setPrivate(true, [item]) } }
                }
                Button("Delete", systemImage: "trash", role: .destructive) { actions.delete([item]) }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Group {
                switch actions.copied {
                case .link:
                    Label("Link copied", systemImage: "doc.on.clipboard")
                case .linkForImage:
                    Label("Link copied — paste it after the image.", systemImage: "doc.on.clipboard")
                case nil:
                    if onDone != nil {
                        Label("Saved to \(Brand.name)", systemImage: "checkmark.circle.fill")
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: .capsule)
            HStack(spacing: 12) {
                if let onDone {
                    share.buttonStyle(.glassProminent)
                    Button(action: onDone) {
                        Text("Done").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                } else if item.url != nil, Opening.canOpenApps {
                    Button {
                        actions.openInApp(item)
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    share.buttonStyle(.glass)
                } else {
                    share.buttonStyle(.glassProminent)
                }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: 520)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var share: some View {
        ShareMenu(item: item, actions: actions) {
            Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
        }
        .disabled(item.isImage && image == nil)
    }
}

private struct TagRow: View {
    let item: LibraryItem
    let actions: ItemActions

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                TagChip(text: item.domainLabel,
                        systemImage: item.isImage ? "photo" : "globe",
                        icon: item.isImage ? nil : actions.library.favicon(item),
                        isSelected: false)
                if item.isPrivate {
                    TagChip(text: String(localized: "Private"), systemImage: "lock.fill", isSelected: false)
                }
                ForEach(item.tags, id: \.self) { tag in
                    TagChip(text: "#\(tag)", isSelected: false)
                }
                Button("Add Tag", systemImage: "plus") { actions.editTags([item]) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct RecognizedText: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Text in Image").font(.headline)
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
                    .labelStyle(.iconOnly)
            }
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : 6)
                .textSelection(.enabled)
            if !expanded, text.split(separator: "\n").count > 6 {
                Button("Show All") { expanded = true }.font(.footnote)
            }
        }
        .padding()
        .background(.fill.quinary, in: .rect(cornerRadius: 16))
    }
}

struct TagChip: View {
    let text: String
    var systemImage: String?
    var icon: UIImage?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .clipShape(.rect(cornerRadius: 4, style: .continuous))
            } else if let systemImage {
                Image(systemName: systemImage).imageScale(.small)
            }
            Text(text).lineLimit(1)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary), in: .capsule)
    }
}
