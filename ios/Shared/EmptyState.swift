import SwiftUI

struct EmptyState: View {
    var showsSample = true
    var showsPaste = true
    let paste: ([NSItemProvider]) -> Void
    var onSample: ((URL) -> Void)?

    @AppStorage("seenShareGuide") private var seenShareGuide = false

    var body: some View {
        VStack(spacing: 24) {
            if !seenShareGuide { pinGuideLink }

            if showsSample { SampleCard() }

            // Simplified Chinese pitches sending these links to WeChat, which shows them bare; other languages pitch one library.
            VStack(spacing: 8) {
                Text("All your links in one place")
                    .font(.title2.bold())
                Text("Save links from YouTube, X and any other site. No feed, no algorithm, no tracking.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            if showsPaste {
                PasteButton(supportedContentTypes: ItemProviders.pasteTypes, payloadAction: paste)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
            }

            VStack(alignment: .leading, spacing: 16) {
                StepRow(number: 1, symbol: "link", text: "Copy a link, or share it to \(Brand.name) from any app")
                StepRow(number: 2, symbol: "photo.on.rectangle.angled", text: "Get a card with the title, cover and QR code")
                StepRow(number: 3, symbol: "message", text: "Send the image anywhere, then paste the link — it's already copied")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.fill.quinary, in: .rect(cornerRadius: 16))

            if seenShareGuide { pinGuideLink }

            if let onSample { sampleLink(onSample) }
        }
    }

    /// A first link to save, so the library is never a dead end.
    private func sampleLink(_ save: @escaping (URL) -> Void) -> some View {
        HStack(spacing: 12) {
            AttentionGlyph(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(Brand.name).font(.subheadline.weight(.semibold))
                Text("Try saving this link")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Add") { save(Brand.appStoreURL) }
                .font(.subheadline.weight(.bold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
        .padding(12)
        .background(.fill.quinary, in: .rect(cornerRadius: 16))
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
        .accessibilityLabel(Text("Step \(number): \(Text(text))"))
    }
}

struct SampleCard: View {
    static let meta = LinkMeta(url: URL(string: "https://youtu.be/0_DjDdfqtUE")!, site: "YouTube",
                               title: "WWDC 2025 — June 9 | Apple",
                               authorName: "Apple")

    var scale: CGFloat = 0.42

    var body: some View {
        let size = CardView.size(for: Self.meta, style: CardStyle())
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
