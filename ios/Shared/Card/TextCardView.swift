import SwiftUI

/// A single readable excerpt. The saved body remains available through Copy/Share Text.
struct TextCardView: View {
    let text: String
    var showsAppStoreQR = true

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
            BrandedCardFooter(tint: tint, qrURL: showsAppStoreQR ? Brand.appStoreURL : nil)
        }
        .padding(24)
        .frame(width: CardView.width)
        .background(tint.color)
        .environment(\.dynamicTypeSize, .large)
    }
}

enum TextCardRenderer {
    static func render(_ text: String, showsAppStoreQR: Bool = true) -> PlatformImage? {
        // Bound layout work even for book-length captures, without changing the stored body.
        let end = text.index(text.startIndex, offsetBy: 8_192, limitedBy: text.endIndex) ?? text.endIndex
        let excerpt = String(text[..<end]) + (end == text.endIndex ? "" : "…")
        let renderer = ImageRenderer(content: TextCardView(text: excerpt, showsAppStoreQR: showsAppStoreQR))
        renderer.proposedSize = ProposedViewSize(width: CardView.width, height: nil)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.platformImage
    }
}

/// Shared by text-image previews and exports, including the iOS share extension.
enum TextCardPromotion {
    static let key = "textCardShowsAppStoreQR"

    static func isEnabled(in defaults: UserDefaults = AppGroup.defaults) -> Bool {
        defaults.object(forKey: key) == nil || defaults.bool(forKey: key)
    }
}
