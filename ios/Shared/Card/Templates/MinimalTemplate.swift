import SwiftUI

struct MinimalTemplate: View {
    let meta: LinkMeta
    let palette: CardPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                SiteChip(meta: meta, palette: palette)
                Spacer(minLength: 8)
                if let image = meta.image ?? meta.largeIcon {
                    Image(platformImage: image)
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
                .lineLimit(CardMetrics.minimalLines)
                .fixedSize(horizontal: false, vertical: true)
            if let byline = meta.byline {
                Text(byline)
                    .font(.system(size: 15))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            CardFooter(meta: meta, palette: palette, qrSize: CardMetrics.footerQRSize)
                .padding(.top, 18)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            LinearGradient(colors: [palette.accent.opacity(0.14), .clear],
                           startPoint: .topLeading, endPoint: .center)
        }
    }
}
