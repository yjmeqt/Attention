import SwiftUI

/// A single readable excerpt. The saved body remains available through Copy/Share Text.
struct TextCardView: View {
    let text: String

    var body: some View {
        let palette = CardPalette(kind: .web)
        Text(verbatim: text)
            .font(.system(size: 22))
            .foregroundStyle(palette.primary)
            .lineSpacing(5)
            .lineLimit(16)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .frame(width: CardView.width)
            .background(palette.background)
            .environment(\.dynamicTypeSize, .large)
    }
}

enum TextCardRenderer {
    static func render(_ text: String) -> PlatformImage? {
        // Bound layout work even for book-length captures, without changing the stored body.
        let end = text.index(text.startIndex, offsetBy: 8_192, limitedBy: text.endIndex) ?? text.endIndex
        let excerpt = String(text[..<end]) + (end == text.endIndex ? "" : "…")
        let renderer = ImageRenderer(content: TextCardView(text: excerpt))
        renderer.proposedSize = ProposedViewSize(width: CardView.width, height: nil)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.platformImage
    }
}
