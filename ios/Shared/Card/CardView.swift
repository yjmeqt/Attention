import SwiftUI

struct CardView: View {
    let meta: LinkMeta
    let style: CardStyle

    var body: some View {
        let palette = CardPalette(kind: meta.kind)
        let metrics = CardMetrics(aspect: style.aspect)
        Group {
            switch style.template.resolved(for: meta) {
            case .auto, .hero: HeroTemplate(meta: meta, palette: palette, metrics: metrics)
            case .post: PostTemplate(meta: meta, palette: palette, metrics: metrics)
            case .minimal: MinimalTemplate(meta: meta, palette: palette, metrics: metrics)
            case .qr: QRTemplate(meta: meta, palette: palette, metrics: metrics)
            }
        }
        .frame(width: metrics.size.width, height: metrics.size.height, alignment: .topLeading)
        .background(palette.background)
        .clipped()
        .environment(\.dynamicTypeSize, .large)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .typesettingLanguage(Locale.Language(identifier: "zh-Hans"))
    }
}

enum CardRenderer {
    static func render(_ meta: LinkMeta, style: CardStyle, scale: CGFloat = 3) -> UIImage? {
        let renderer = ImageRenderer(content: CardView(meta: meta, style: style))
        renderer.proposedSize = ProposedViewSize(style.aspect.size)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
