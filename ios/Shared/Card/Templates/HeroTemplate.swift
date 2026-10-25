import SwiftUI

struct HeroTemplate: View {
    let meta: LinkMeta
    let palette: CardPalette
    let metrics: CardMetrics

    var body: some View {
        let imageHeight = metrics.heroImageHeight(for: meta.imageAspectRatio)
        VStack(alignment: .leading, spacing: 0) {
            HeroImage(meta: meta, palette: palette, size: CGSize(width: metrics.size.width, height: imageHeight))
                .frame(width: metrics.size.width, height: imageHeight)
                .clipped()
                .overlay {
                    if meta.kind.isVideo, meta.image != nil { PlayGlyph() }
                }
                .overlay(alignment: .topLeading) {
                    SiteChip(meta: meta, palette: palette).padding(12)
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(meta.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .lineSpacing(2)
                    .lineLimit(metrics.heroTitleLines(imageHeight: imageHeight,
                                                      hasByline: meta.byline != nil))
                if let byline = meta.byline {
                    Text(byline)
                        .font(.system(size: 15))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                CardFooter(meta: meta, palette: palette, qrSize: metrics.footerQRSize)
            }
            .padding(metrics.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
