import SwiftUI

struct CardMakerView: View {
    var initialURL: URL?
    var watchesClipboard = false
    var allowsScanning = false
    var onDone: (() -> Void)?

    @State private var maker = CardMaker()
    @State private var isWide = false
    @State private var cardPaneHeight: CGFloat = .infinity
    @State private var showHistory = false
    @State private var clipboardHasLink = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            content
                .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { isWide = $0 }
                .navigationTitle(Brand.name)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("History", systemImage: "clock.arrow.circlepath") { showHistory = true }
                    }
                    if let onDone {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .close, action: onDone)
                        }
                    }
                }
                .sheet(isPresented: $showHistory) { HistoryView(maker: maker) }
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    maker.input = url.absoluteString
                    Task { await maker.make() }
                    return true
                }
        }
        .task {
            guard let initialURL else { return }
            maker.input = initialURL.absoluteString
            maker.autoSharePending = true
            await maker.make()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            maker.history.reload()
            if watchesClipboard { clipboardHasLink = await Clipboard.hasNewLink() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isWide {
            if #available(iOS 27.1, *) {
                ArrangementView {
                    ScrollView { InputPane(maker: maker, clipboardHasLink: $clipboardHasLink, isWide: true, allowsScanning: allowsScanning) }
                } secondary: {
                    wideCardPane
                }
                .arrangementViewStyle(.split.axes(.horizontal))
            } else {
                HStack(spacing: 0) {
                    ScrollView { InputPane(maker: maker, clipboardHasLink: $clipboardHasLink, isWide: true, allowsScanning: allowsScanning) }
                    wideCardPane
                }
            }
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    InputPane(maker: maker, clipboardHasLink: $clipboardHasLink, allowsScanning: allowsScanning)
                    if maker.card != nil { CardPane(maker: maker) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var wideCardPane: some View {
        ScrollView {
            CardPane(maker: maker, maxCardHeight: max(cardPaneHeight - 140, 240))
                .frame(minHeight: cardPaneHeight.isFinite ? cardPaneHeight : 0)
        }
        .background(.fill.quinary)
        .onGeometryChange(for: CGFloat.self) { $0.size.height - $0.safeAreaInsets.top - $0.safeAreaInsets.bottom } action: { cardPaneHeight = $0 }
    }
}

struct InputPane: View {
    @Bindable var maker: CardMaker
    @Binding var clipboardHasLink: Bool
    var isWide = false
    var allowsScanning = false
    @FocusState private var fieldFocused: Bool
    @State private var showScanner = false
    @State private var selection: TextSelection?

    private var isEmpty: Bool { maker.card == nil && !maker.loading }

    var body: some View {
        VStack(spacing: 16) {
            if clipboardHasLink {
                HStack {
                    Label("You copied a link", systemImage: "link")
                    Spacer()
                    PasteButton(supportedContentTypes: ItemProviders.linkTypes, payloadAction: use)
                }
                .padding(12)
                .background(.thinMaterial, in: .rect(cornerRadius: 12))
            }
            HStack {
                TextField("Paste a link", text: $maker.input, selection: $selection)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($fieldFocused)
                    .onSubmit(generate)
                    .onChange(of: maker.input) { if fieldFocused { maker.notice = nil } }
                    .onChange(of: fieldFocused) { _, focused in
                        guard focused, !maker.input.isEmpty else { return }
                        selection = TextSelection(range: maker.input.startIndex..<maker.input.endIndex)
                    }
                if !maker.input.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") {
                        maker.input = ""
                        selection = nil
                        fieldFocused = true
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                }
                if !isEmpty {
                    PasteButton(supportedContentTypes: ItemProviders.linkTypes, payloadAction: use)
                        .labelStyle(.iconOnly)
                }
                if allowsScanning {
                    Button("Scan QR Code", systemImage: "qrcode.viewfinder") {
                        fieldFocused = false
                        showScanner = true
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScanSheet { url in
                    maker.input = url.absoluteString
                    Task { await maker.make() }
                }
            }
            if maker.loading || (!maker.input.isEmpty && maker.input != maker.meta?.url.absoluteString) {
                Button("Generate", action: generate)
                    .buttonStyle(.glass)
                    .disabled(maker.loading)
            }
            if maker.loading { ProgressView() }
            if let notice = maker.notice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
            }
            if isEmpty {
                EmptyState(maker: maker, showsSample: !isWide, showsPaste: !clipboardHasLink, paste: use)
                    .padding(.top, 8)
            } else if isWide, let meta = maker.meta {
                CurrentLinkSummary(meta: meta)
                    .padding(.top, 8)
                RecentList(maker: maker, limit: 5, excluding: meta.url)
            }
        }
        .frame(maxWidth: 520)
        .padding()
        .frame(maxWidth: .infinity)
    }

    private func generate() {
        fieldFocused = false
        Task { await maker.make() }
    }

    private func use(_ providers: [NSItemProvider]) {
        Clipboard.ignoreCurrent()
        clipboardHasLink = false
        fieldFocused = false
        Task {
            guard let url = await ItemProviders.firstLink(in: providers) else {
                maker.notice = "No link found on the clipboard."
                return
            }
            maker.input = url.absoluteString
            await maker.make()
        }
    }
}

struct CardPane: View {
    @Bindable var maker: CardMaker
    var maxCardHeight: CGFloat = .infinity
    @State private var presenter = SharePresenter()
    @State private var linkCopied = false
    @State private var showStyle = false

    var body: some View {
        Group {
            if let card = maker.card {
                VStack(spacing: 16) {
                    Image(uiImage: card)
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: 16))
                        .shadow(radius: 4)
                        .frame(maxHeight: maxCardHeight)
                        .accessibilityLabel(maker.meta?.title ?? "Card")

                    HStack(spacing: 12) {
                        Button(action: share) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.glassProminent)
                        .background(ShareAnchor(presenter: presenter))
                        Button("Style", systemImage: "slider.horizontal.3") { showStyle = true }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.glass)
                    }
                    .controlSize(.large)

                    if linkCopied {
                        Label("Link copied — paste it after the image.", systemImage: "doc.on.clipboard")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(spacing: 20) {
                    SampleCard(scale: 0.7)
                    Text("Your card will appear here")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)
            }
        }
        .frame(maxWidth: 520)
        .padding()
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showStyle) {
            StyleSheet(maker: maker)
                .presentationDetents([.medium, .large])
        }
        .task(id: maker.card) {
            guard maker.autoSharePending, maker.card != nil else { return }
            maker.autoSharePending = false
            try? await Task.sleep(for: .milliseconds(300))
            share()
        }
    }

    private func share() {
        guard let card = maker.card, let url = maker.meta?.shareURL else { return }
        Clipboard.copy(url)
        linkCopied = true
        presenter.present([card])
    }
}

struct StyleSheet: View {
    @Bindable var maker: CardMaker
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let meta = maker.meta {
                        Text("Template").font(.headline)
                        TemplatePicker(meta: meta, style: $maker.style)
                    }
                    Text("Aspect ratio").font(.headline)
                    Picker("Aspect ratio", selection: $maker.style.aspect) {
                        ForEach(CardAspect.allCases) { Text($0.label) }
                    }
                    .pickerStyle(.segmented)
                    if let meta = maker.meta { SourceImageInfo(meta: meta) }
                    if maker.style != CardStyle() {
                        Button("Restore default", systemImage: "arrow.counterclockwise") { maker.style = CardStyle() }
                    }
                }
                .padding()
            }
            .navigationTitle("Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}

private struct CurrentLinkSummary: View {
    let meta: LinkMeta

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                FaviconView(meta: meta, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(meta.hasPreview ? meta.title : meta.displayURL)
                        .font(.headline)
                        .lineLimit(3)
                    if let byline = meta.byline {
                        Text(byline).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Divider()
            Link(destination: meta.url) {
                Label(meta.displayURL, systemImage: "safari")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.footnote)
            SourceImageInfo(meta: meta)
        }
        .padding()
        .background(.fill.quinary, in: .rect(cornerRadius: 16))
    }
}

struct SourceImageInfo: View {
    let meta: LinkMeta

    var body: some View {
        Group {
            if let size = meta.imagePixelSize {
                let small = size.width < 800
                Label("Source image \(Int(size.width)) × \(Int(size.height))\(small ? " · low resolution" : "")",
                      systemImage: small ? "exclamationmark.triangle" : "photo")
                    .foregroundStyle(small ? .orange : .secondary)
            } else if meta.hasPreview {
                Label("No source image", systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TemplatePicker: View {
    let meta: LinkMeta
    @Binding var style: CardStyle

    private let scale: CGFloat = 0.2

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(CardTemplate.allCases) { template in
                    Button {
                        style.template = template
                    } label: {
                        VStack(spacing: 6) {
                            thumbnail(template)
                            Text(template == .auto ? "Auto · \(template.resolved(for: meta).label)" : template.label)
                                .font(.caption)
                                .foregroundStyle(style.template == template ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(template.label)
                    .accessibilityAddTraits(style.template == template ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func thumbnail(_ template: CardTemplate) -> some View {
        var thumbStyle = style
        thumbStyle.template = template
        let size = style.aspect.size
        let selected = style.template == template
        return CardView(meta: meta, style: thumbStyle)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
            .clipShape(.rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 2 : 1)
            }
            .accessibilityHidden(true)
    }
}

struct HistoryView: View {
    let maker: CardMaker
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(maker.history.entries) { entry in
                    Button {
                        maker.show(maker.history.meta(for: entry))
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            FaviconView(meta: entry.meta, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.meta.hasPreview ? entry.meta.title : entry.meta.displayURL).lineLimit(2)
                                Text("\(entry.meta.site) · \(entry.date.formatted(.relative(presentation: .named)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { offsets in
                    offsets.map { maker.history.entries[$0] }.forEach(maker.history.remove)
                }
            }
            .overlay {
                if maker.history.entries.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: "clock")
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}
