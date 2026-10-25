import SwiftUI

struct PostTemplate: View {
    let meta: LinkMeta
    let palette: CardPalette
    let metrics: CardMetrics

    private var mediaHeight: CGFloat { metrics.postMediaHeight(for: meta.imageAspectRatio) }
    private var media: UIImage? { mediaHeight > 0 && !meta.imageIsIcon ? meta.image : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Avatar(meta: meta, palette: palette)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meta.authorName ?? meta.site)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.primary)
                    if let handle = meta.authorHandle {
                        Text(verbatim: "@" + handle)
                            .font(.system(size: 14))
                            .foregroundStyle(palette.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                SiteChip(meta: meta, palette: palette)
            }
            Text(meta.title)
                .font(.system(size: 19))
                .foregroundStyle(palette.primary)
                .lineSpacing(3)
                .lineLimit(metrics.postLines(withMedia: media != nil))
            if let media {
                Image(uiImage: media)
                    .resizable()
                    .scaledToFill()
                    .frame(width: metrics.size.width - metrics.padding * 2, height: mediaHeight)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay {
                        if meta.kind.isVideo { PlayGlyph() }
                    }
            }
            Spacer(minLength: 0)
            CardFooter(meta: meta, palette: palette, qrSize: metrics.footerQRSize)
        }
        .padding(metrics.padding)
    }
}
