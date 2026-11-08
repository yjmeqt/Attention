import SwiftUI

/// A single readable excerpt. The saved body remains available through Copy/Share Text.
struct TextCardView: View {
    let text: String

    var body: some View {
        let tint = CardTint.neutral
        VStack(alignment: .leading, spacing: 24) {
            Text(verbatim: text)
                .font(.system(size: 22))
                .foregroundStyle(tint.primary)
                .lineSpacing(5)
                .lineLimit(16)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                AttentionGlyph(size: 18)
                Text("Made with \(Brand.name)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint.secondary)
            }
        }
        .padding(24)
        .frame(width: CardView.width)
        .background(tint.color)
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
