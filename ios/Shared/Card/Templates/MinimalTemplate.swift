import SwiftUI

struct MinimalTemplate: View {
    let meta: LinkMeta
    let palette: CardPalette
    let metrics: CardMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                SiteChip(meta: meta, palette: palette)
                Spacer(minLength: 8)
                if let image = meta.image ?? meta.largeIcon {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(.rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14).strokeBorder(palette.primary.opacity(0.08))
                        }
                }
            }
            Text(meta.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(palette.primary)
                .lineSpacing(3)
                .lineLimit(metrics.minimalLines)
            if let byline = meta.byline {
                Text(byline)
                    .font(.system(size: 15))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            CardFooter(meta: meta, palette: palette, qrSize: metrics.footerQRSize)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            LinearGradient(colors: [palette.accent.opacity(0.14), .clear],
                           startPoint: .topLeading, endPoint: .center)
        }
    }
}
