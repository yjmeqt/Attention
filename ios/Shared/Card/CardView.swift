import SwiftUI

struct CardView: View {
    let meta: LinkMeta
    let style: CardStyle
    /// Set when rendering, so the image is exactly the measured size.
    var height: CGFloat?

    var body: some View {
        let palette = CardPalette(kind: meta.kind)
        Group {
            switch style.template.resolved(for: meta) {
            case .auto, .tile: TileTemplate(meta: meta)
            case .minimal: MinimalTemplate(meta: meta, palette: palette)
            case .qr: QRTemplate(meta: meta, palette: palette)
            }
        }
        .frame(width: Self.width, height: height, alignment: .topLeading)
        .background(palette.background)
        .clipped()
        .environment(\.dynamicTypeSize, .large)
    }

    /// Points; rendered at 3x (1080 px).
    static let width = TileTemplate.width

    /// Points. Every template is as tall as its content.
    static func size(for meta: LinkMeta, style: CardStyle) -> CGSize {
        let fitting = UIHostingController(rootView: CardView(meta: meta, style: style))
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitting.height.rounded(.up))
    }
}

enum CardRenderer {
    static func render(_ meta: LinkMeta, style: CardStyle, scale: CGFloat = 3) -> UIImage? {
        let size = CardView.size(for: meta, style: style)
        let renderer = ImageRenderer(content: CardView(meta: meta, style: style, height: size.height))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
