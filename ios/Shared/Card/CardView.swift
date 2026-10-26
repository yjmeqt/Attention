import SwiftUI

struct CardView: View {
    let meta: LinkMeta
    let style: CardStyle

    var body: some View {
        let palette = CardPalette(kind: meta.kind)
        let metrics = CardMetrics(aspect: style.aspect)
        let template = style.template.resolved(for: meta)
        Group {
            switch template {
            case .auto, .tile: TileTemplate(meta: meta)
            case .hero: HeroTemplate(meta: meta, palette: palette, metrics: metrics)
            case .post: PostTemplate(meta: meta, palette: palette, metrics: metrics)
            case .minimal: MinimalTemplate(meta: meta, palette: palette, metrics: metrics)
            case .qr: QRTemplate(meta: meta, palette: palette, metrics: metrics)
            }
        }
        .frame(width: metrics.size.width, height: template == .tile ? nil : metrics.size.height, alignment: .topLeading)
        .background(palette.background)
        .clipped()
        .environment(\.dynamicTypeSize, .large)
    }

    /// Points. Fixed by the aspect ratio, except the tile, which takes its photo's shape.
    static func size(for meta: LinkMeta, style: CardStyle) -> CGSize {
        guard style.template.resolved(for: meta) == .tile else { return style.aspect.size }
        let fitting = UIHostingController(rootView: CardView(meta: meta, style: style))
            .sizeThatFits(in: CGSize(width: TileTemplate.width, height: .greatestFiniteMagnitude))
        return CGSize(width: TileTemplate.width, height: fitting.height.rounded(.up))
    }
}

enum CardRenderer {
    static func render(_ meta: LinkMeta, style: CardStyle, scale: CGFloat = 3) -> UIImage? {
        let renderer = ImageRenderer(content: CardView(meta: meta, style: style))
        renderer.proposedSize = ProposedViewSize(CardView.size(for: meta, style: style))
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
