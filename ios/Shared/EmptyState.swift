import SwiftUI

struct EmptyState: View {
    let maker: CardMaker
    var showsSample = true
    var showsPaste = true
    let paste: ([NSItemProvider]) -> Void

    @AppStorage("seenShareGuide") private var seenShareGuide = false

    var body: some View {
        VStack(spacing: 24) {
            if !seenShareGuide { pinGuideLink }

            if showsSample { SampleCard() }

            VStack(spacing: 8) {
                Text("Links WeChat can preview")
                    .font(.title2.bold())
                Text("YouTube, X and many sites show up in WeChat as a bare link. Turn them into an image card with the title, cover and a QR code.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            if showsPaste {
                PasteButton(supportedContentTypes: ItemProviders.linkTypes, payloadAction: paste)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
            }

            VStack(alignment: .leading, spacing: 16) {
                StepRow(number: 1, symbol: "link", text: "Copy a link, or share it to \(Brand.name) from any app")
                StepRow(number: 2, symbol: "photo.on.rectangle.angled", text: "Get a card with the title, cover and QR code")
                StepRow(number: 3, symbol: "message", text: "Send the image in WeChat, then paste the link — it's already copied")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.fill.quinary, in: .rect(cornerRadius: 16))

            RecentList(maker: maker)

            if seenShareGuide { pinGuideLink }
        }
    }

    private var pinGuideLink: some View {
        NavigationLink {
            ShareSheetGuide()
                .onDisappear { seenShareGuide = true }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: seenShareGuide ? "lightbulb" : "pin.fill")
                    .foregroundStyle(.tint)
                Text("Pin \(Brand.name) to the front of the share sheet")
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(seenShareGuide ? .footnote : .subheadline.weight(.medium))
            .padding(12)
            .background(seenShareGuide ? AnyShapeStyle(.fill.quinary) : AnyShapeStyle(.tint.opacity(0.12)),
                        in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

}

struct RecentList: View {
    let maker: CardMaker
    var limit = 3
    var excluding: URL?

    var body: some View {
        let entries = Array(maker.history.entries.filter { $0.meta.url != excluding }.prefix(limit))
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent").font(.headline).padding(.bottom, 4)
                rows(entries)
            }
        }
    }

    private func rows(_ entries: [HistoryEntry]) -> some View {
        ForEach(entries) { entry in
                Button {
                    maker.show(maker.history.meta(for: entry))
                } label: {
                    HStack(spacing: 12) {
                        FaviconView(meta: entry.meta)
                        Text(entry.meta.hasPreview ? entry.meta.title : entry.meta.displayURL)
                            .lineLimit(1)
                        Spacer()
                        Text(entry.meta.site)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if entry.id != entries.last?.id { Divider() }
        }
    }
}

private struct StepRow: View {
    let number: Int
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.quaternary, in: .circle)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Step \(number): ") + Text(text))
    }
}

struct SampleCard: View {
    static let meta = LinkMeta(url: URL(string: "https://youtu.be/dQw4w9WgXcQ")!, site: "YouTube",
                               title: "Rick Astley - Never Gonna Give You Up (Official Video)",
                               authorName: "Rick Astley")

    var scale: CGFloat = 0.42

    var body: some View {
        let size = CardAspect.portrait.size
        CardView(meta: Self.meta, style: CardStyle())
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
            .clipShape(.rect(cornerRadius: 10))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            .rotationEffect(.degrees(-4))
            .padding(.vertical, 8)
            .accessibilityHidden(true)
    }
}
