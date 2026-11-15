import SwiftUI

/// Shares items as a list, the selected ones or a tag's: says what will and won't go, uploads it with its
/// link preview, then shares the link. A picture of the list comes from sharing that link to Attention.
struct ShareListSheet: View {
    let library: Library

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ListDraft
    @State private var title: String
    @State private var phase: Phase = .composing
    @State private var presenter = SharePresenter()

    enum Phase {
        case composing
        case uploading
        case shared(url: URL, preview: PlatformImage?)
        case failed(ListSharingError)
    }

    init(_ request: ShareListRequest, library: Library) {
        self.library = library
        _draft = State(initialValue: ListDraft(items: request.items))
        _title = State(initialValue: request.title)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Share List")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .background { ShareAnchor(presenter: presenter) }
        .interactiveDismissDisabled(isUploading)
    }

    private var isUploading: Bool {
        if case .uploading = phase { return true }
        return false
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .composing, .uploading, .failed:
            if draft.items.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to Share", systemImage: "square.and.arrow.up")
                } description: {
                    Text("Only links and text can be shared as a list. Images and private items stay on your devices.")
                }
            } else {
                form
            }
        case let .shared(url, preview):
            shared(url: url, preview: preview)
        }
    }

    /// The title, then the items as the feed shows them, so it's clear what goes out.
    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("List Title", text: $title)
                        .font(.title2.bold())
                        .submitLabel(.done)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.secondaryBackground, in: .rect(cornerRadius: 14, style: .continuous))
                    Text("People who open the list and save it get its items tagged with this title.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(draft.items.count) items")
                        .font(.headline)
                    ForEach(skippedNotes, id: \.self) { note in
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)

                Waterfall(items: draft.items, columns: horizontalSizeClass == .regular ? 3 : 2) { item in
                    FeedTile(item: item, library: library)
                }

                Text("The list is uploaded to Attention's server, and anyone with the link can see it. Editing these items later doesn't change it. You can take it down from Shared Lists in the sidebar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                if case let .failed(error) = phase {
                    Label(Self.message(for: error), systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(isUploading)
        .overlay {
            if isUploading {
                ProgressView("Sharing…")
                    .padding(24)
                    .background(.regularMaterial, in: .rect(cornerRadius: 16, style: .continuous))
            }
        }
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// What stays behind, and why.
    private var skippedNotes: [String] {
        var notes: [String] = []
        if draft.skipped.privateItems > 0 {
            notes.append(String(localized: "Private items aren't shared: \(draft.skipped.privateItems)"))
        }
        if draft.skipped.images > 0 {
            notes.append(String(localized: "Images aren't shared: \(draft.skipped.images)"))
        }
        if draft.skipped.overLimit > 0 {
            notes.append(String(localized: "A list holds up to \(ListUpload.limits.items) items; left out: \(draft.skipped.overLimit)"))
        }
        return notes
    }

    private func shared(url: URL, preview: PlatformImage?) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                if let preview {
                    Image(platformImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280)
                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                        .accessibilityLabel(Text("Link preview"))
                }
                VStack(spacing: 6) {
                    Label("Shared", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text(verbatim: url.absoluteString)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Text("Apps that show link previews show this picture. To send a picture instead, as in WeChat, share the link to Attention and send its card.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                VStack(spacing: 10) {
                    Button {
                        send(url: url, preview: preview)
                    } label: {
                        Label("Share Link", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        Clipboard.copy(url)
                    } label: {
                        Label("Copy Link", systemImage: "link").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            .padding(20)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch phase {
        case .shared:
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        default:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isUploading)
            }
            if !draft.items.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") { Task { await share() } }
                        .disabled(trimmedTitle.isEmpty || isUploading)
                }
            }
        }
    }

    private func share() async {
        phase = .uploading
        let upload = await ListUpload.make(title: trimmedTitle, draft: draft, library: library)
        let preview = ListCardRenderer.previewJPEG(ListCardContent(title: upload.title, items: draft.items, library: library))
        do {
            let created = try await ListSharingClient.upload(upload, preview: preview)
            library.recordSharedList(SharedListRecord(listID: created.id, title: upload.title,
                                                      itemCount: upload.items.count, deleteToken: created.deleteToken))
            let image = preview.flatMap(PlatformImage.init(data:))
            phase = .shared(url: created.url, preview: image)
            send(url: created.url, preview: image)
        } catch {
            phase = .failed(error)
        }
    }

    /// Copies the link and opens the share sheet with it; the sheet's header shows the list's preview.
    private func send(url: URL, preview: PlatformImage?) {
        Clipboard.copy(url)
        presenter.present([ShareItem(url: url, title: trimmedTitle, icon: nil, image: preview)])
    }

    static func message(for error: ListSharingError) -> String {
        switch error {
        case .rateLimited: String(localized: "Too many lists were shared from this network just now. Try again in a minute.")
        case .dailyLimit: String(localized: "Attention has reached today's limit for shared lists. Try again tomorrow.")
        case .uploadsPaused: String(localized: "Sharing lists is paused for now. Try again later.")
        case .rejected: String(localized: "Attention's server didn't accept this list.")
        case .unavailable: String(localized: "Couldn't reach Attention's server. Check your connection and try again.")
        }
    }
}

/// What to share as a list, and the title it starts with.
struct ShareListRequest {
    let items: [LibraryItem]
    let title: String

    static func tag(_ tag: String, in library: Library) -> ShareListRequest {
        ShareListRequest(items: ListDraft(tag: tag, library: library).items, title: tag)
    }

    /// Picked items get the tag being viewed as their title, or the date.
    static func selection(_ items: [LibraryItem], tag: String?) -> ShareListRequest {
        ShareListRequest(items: items, title: tag ?? String(localized: "Shared \(Date.now.formatted(.dateTime.month().day()))"))
    }
}
