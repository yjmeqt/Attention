import SwiftUI

/// A saved item: its card (or image), style, tags and actions. Used by the app and the share extension.
struct ItemDetailView: View {
    @AppStorage(TextCardPromotion.key, store: AppGroup.defaults) private var showsAppStoreQR = true
    let item: LibraryItem
    /// Set in the share extension: shows a Done button that closes it.
    var onDone: (() -> Void)?
    /// Opens the share sheet with the card as soon as the view is up, for the Share suggestion.
    var autoShare = false

    @State private var actions: ItemActions
    @State private var image: UIImage?
    @State private var presentedCover: PresentedCover?
    /// A link's preview image, the image it was shared as and the one the user picked, each if it has one.
    @State private var covers: (preview: UIImage?, shared: UIImage?, custom: UIImage?)?
    /// Set when Reload Preview can't fetch a usable card.
    @State private var enrichNotice: String?
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
        Group {
            if library.contains(item) { content }
        }
        .onChange(of: library.contains(item)) { _, available in
            if !available {
                if let onDone { onDone() } else { dismiss() }
            }
        }
    }

    private var content: some View {
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
        .fullScreenCover(item: $presentedCover) { cover in
            CoverGallery(presentation: cover, selectedCover: coverBinding)
        }
        .task(id: "\(showsAppStoreQR)-\(library.revision)-\(item.templateRaw)") {
            guard !Task.isCancelled, library.contains(item) else { return }
            image = library.fullImage(item)
            covers = item.isImage ? nil
                : (library.previewData(item).flatMap(Self.coverThumbnail),
                   library.data(.source, of: item).flatMap(Self.coverThumbnail),
                   library.data(.custom, of: item).flatMap(Self.coverThumbnail))
        }
        .task {
            guard autoShare else { return }
            // The share anchor needs to be in the window before the sheet can present from it.
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard !Task.isCancelled, library.contains(item) else { return }
            actions.shareImage(item)
        }
        .onAppear {
            actions.notice = nil
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

    private var imageButtons: some View {
        HStack(spacing: 12) {
            Button {
                actions.copyImage(item)
            } label: {
                Label("Copy Image", systemImage: "photo")
            }
            .disabled(image == nil)
            if item.url != nil {
                Button {
                    actions.copyLink(item)
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
            }
            Button {
                Task { await actions.saveToPhotos(item) }
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
            }
            .disabled(image == nil)
        }
        .labelStyle(StackedLabelStyle())
        .buttonStyle(.bordered)
        .tint(.primary)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 20) {
            imageButtons
            if let text = item.text {
                HStack {
                    Button("Copy Text", systemImage: "doc.on.doc") { actions.copyText(item) }
                    Button("Share Text", systemImage: "square.and.arrow.up") { actions.shareText(item) }
                }
                .buttonStyle(.bordered)
                Text(verbatim: text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                        CoverPicker(preview: covers.preview, shared: covers.shared, custom: covers.custom, cover: coverBinding) {
                            library.setCustomImage($0, for: item)
                        } removeCustom: {
                            library.removeCustomImage(item)
                        } onPreview: { cover, namespace in
                            showCover(cover, namespace: namespace)
                        }
                    }
                    Text("Template").font(.headline)
                    TemplatePicker(meta: meta, style: styleBinding)
                    if !isLoading { SourceImageInfo(meta: meta) }
                    Button {
                        reloadPreview()
                    } label: {
                        Label("Reload Preview", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }

            if let text = item.ocrText, !text.isEmpty {
                RecognizedText(text: text)
            }
        }
    }

    private var coverBinding: Binding<Library.Cover> {
        Binding { library.contains(item) ? library.cover(of: item) : .preview } set: {
            guard library.contains(item) else { return }
            library.setCover($0, for: item)
        }
    }

    private static func coverThumbnail(_ data: Data) -> UIImage? {
        ImageData.downsample(data, maxPixel: 300).map(UIImage.init(cgImage:))
    }

    private func showCover(_ cover: Library.Cover, namespace: Namespace.ID) {
        guard library.contains(item) else { return }
        let candidates: [(Library.Cover, String, Data?)] = [
            (.preview, String(localized: "Link Preview"), library.previewData(item)),
            (.shared, String(localized: "Shared Image"), library.data(.source, of: item)),
            (.custom, String(localized: "Your Image"), library.data(.custom, of: item))
        ]
        let pages = candidates.compactMap { source, title, data -> CoverPage? in
            guard let data else { return nil }
            return CoverPage(id: source, title: title, data: data)
        }
        guard pages.contains(where: { $0.id == cover }) else { return }
        presentedCover = PresentedCover(pages: pages, source: cover, namespace: namespace)
    }

    private var styleBinding: Binding<CardStyle> {
        Binding {
            library.contains(item) ? item.style : CardStyle()
        } set: { style in
            guard library.contains(item) else { return }
            library.setStyle(style, for: item)
            style.save()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if onDone == nil {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .close) { dismiss() }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu("More", systemImage: "ellipsis") {
                if item.url != nil {
                    if Opening.canOpenApps {
                        Button("Open in App", systemImage: "arrow.up.forward.app") { actions.openInApp(item) }
                    }
                    Button("Open in Browser", systemImage: "safari") { actions.openInBrowser(item) }
                    Button("Reload Preview", systemImage: "arrow.clockwise") { reloadPreview() }
                        .disabled(isLoading)
                }
                Button("Edit Tags…", systemImage: "tag") { actions.editTags([item]) }
                if item.isPrivate {
                    Button("Remove from Private", systemImage: "lock.open") { Task { await actions.setPrivate(false, [item]) } }
                } else {
                    Button("Move to Private", systemImage: "lock") { Task { await actions.setPrivate(true, [item]) } }
                }
                Button(item.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox") {
                    actions.setArchived(!item.isArchived, [item])
                }
                Button("Delete", systemImage: "trash", role: .destructive) { actions.delete([item]) }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if showsStatus {
                statusLabel
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: .capsule)
            }
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
        ShareMenu(item: item, actions: actions, sharesOnTap: true) {
            Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
        }
        .disabled(item.isImage && image == nil)
    }

    private var showsStatus: Bool {
        actions.notice != nil || enrichNotice != nil || onDone != nil
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch actions.notice {
        case .textCopied:
            Label("Text copied", systemImage: "doc.on.clipboard")
        case .linkCopied:
            Label("Link copied", systemImage: "doc.on.clipboard")
        case .linkCopiedForImage:
            Label("Link copied — paste it after the image.", systemImage: "doc.on.clipboard")
        case .imageCopied:
            Label("Image copied", systemImage: "doc.on.clipboard")
        case .savedToPhotos:
            Label("Saved to Photos", systemImage: "checkmark.circle.fill")
        case .photosDenied:
            Label("Allow Photos access in Settings to save.", systemImage: "exclamationmark.triangle")
        case .photosSaveFailed:
            Label("Couldn't save to Photos.", systemImage: "exclamationmark.triangle")
        case nil:
            if let enrichNotice {
                Label(enrichNotice, systemImage: "exclamationmark.triangle")
            } else {
                Label("Saved to \(Brand.name)", systemImage: "checkmark.circle.fill")
            }
        }
    }

    private func reloadPreview() {
        guard library.contains(item), !isLoading else { return }
        actions.notice = nil
        enrichNotice = nil
        Task {
            enrichNotice = await library.enrich(item)
        }
    }
}

private struct CoverPage: Identifiable {
    let id: Library.Cover
    let title: String
    let data: Data
}

private struct PresentedCover: Identifiable {
    let id = UUID()
    let pages: [CoverPage]
    let source: Library.Cover
    let namespace: Namespace.ID
}

private struct CoverGallery: View {
    let presentation: PresentedCover
    @Binding var selectedCover: Library.Cover
    @State private var current: Library.Cover
    @Environment(\.dismiss) private var dismiss

    init(presentation: PresentedCover, selectedCover: Binding<Library.Cover>) {
        self.presentation = presentation
        _selectedCover = selectedCover
        _current = State(initialValue: presentation.source)
    }

    private var index: Int { presentation.pages.firstIndex(where: { $0.id == current }) ?? 0 }
    private var isSelected: Bool { selectedCover == current }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.pages[index].title).font(.headline)
                    Text("\(index + 1) / \(presentation.pages.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(.primary)
            }
            .padding()

            TabView(selection: $current) {
                ForEach(presentation.pages) { page in
                    CoverGalleryPage(page: page, onDismiss: { dismiss() })
                        .tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))


            Button {
                selectedCover = current
                dismiss()
            } label: {
                Label(isSelected ? "Currently Used" : "Use as Cover",
                      systemImage: isSelected ? "checkmark.circle.fill" : "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(isSelected)
            .frame(maxWidth: 420)
            .padding()
        }
        .background(Color.secondaryBackground.ignoresSafeArea())
        .interactiveDismissDisabled()
        .navigationTransition(.zoom(sourceID: current, in: presentation.namespace))
    }
}

private struct CoverGalleryPage: View {
    let page: CoverPage
    let onDismiss: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                ZoomableImageView(image: image, onDismiss: onDismiss)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: page.id) {
            image = ImageData.downsample(page.data, maxPixel: 4096).map(UIImage.init(cgImage:))
        }
    }
}

private struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIView(context: Context) -> ZoomScrollView {
        let scrollView = ZoomScrollView(frame: .zero)
        scrollView.backgroundColor = .clear
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.delegate = context.coordinator
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never

        scrollView.imageView.image = image

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        let dismissPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.dragToDismiss(_:)))
        dismissPan.maximumNumberOfTouches = 1
        dismissPan.delegate = context.coordinator
        scrollView.addGestureRecognizer(dismissPan)
        return scrollView
    }

    func updateUIView(_ scrollView: ZoomScrollView, context: Context) {
        scrollView.imageView.image = image
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ZoomScrollView)?.centerImage()
        }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer,
                  let scrollView = pan.view as? UIScrollView, scrollView.zoomScale <= 1.01 else { return false }
            let velocity = pan.velocity(in: scrollView)
            return velocity.y > abs(velocity.x) * 1.5
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        @objc func dragToDismiss(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .ended, gesture.translation(in: gesture.view).y > 100 else { return }
            onDismiss()
        }

        @objc func toggleZoom(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? ZoomScrollView else { return }
            if scrollView.zoomScale > 1 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let zoom: CGFloat = 2.5
                let point = gesture.location(in: scrollView.imageView)
                let size = CGSize(width: scrollView.bounds.width / zoom, height: scrollView.bounds.height / zoom)
                scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                           width: size.width, height: size.height), animated: true)
            }
        }
    }
}

private final class ZoomScrollView: UIScrollView {
    let imageView = UIImageView()
    private var laidOutSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize, bounds.width > 0, bounds.height > 0,
              let image = imageView.image, image.size.width > 0, image.size.height > 0 else { return }
        laidOutSize = bounds.size
        setZoomScale(1, animated: false)
        let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * fit, height: image.size.height * fit)
        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        centerImage()
    }

    func centerImage() {
        let horizontal = max(0, (bounds.width - imageView.frame.width) / 2)
        let vertical = max(0, (bounds.height - imageView.frame.height) / 2)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }
}

/// Icon over title, so three buttons fit side by side on a phone.
private struct StackedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 4) {
            configuration.icon.imageScale(.large).frame(height: 24)
            configuration.title.font(.caption).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

private struct TagRow: View {
    let item: LibraryItem
    let actions: ItemActions

    var body: some View {
        if actions.library.contains(item) { content }
    }

    private var content: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                TagChip(text: item.domainLabel,
                        systemImage: item.isTextOnly ? "text.alignleft" : item.isImage ? "photo" : "globe",
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
                Button("Copy", systemImage: "doc.on.doc") { Clipboard.copy(text) }
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
