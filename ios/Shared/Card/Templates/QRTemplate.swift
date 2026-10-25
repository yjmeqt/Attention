import SwiftUI

struct QRTemplate: View {
    let meta: LinkMeta
    let palette: CardPalette
    let metrics: CardMetrics

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                SiteChip(meta: meta, palette: palette)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            QRBadge(url: meta.shareURL, size: metrics.bigQRSize, palette: palette, caption: "长按识别二维码打开",
                    logo: meta.largeIcon)
            Text(meta.hasPreview ? meta.title : meta.displayURL)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if !meta.hasPreview {
                Text(verbatim: "无法获取预览，可识别二维码或粘贴链接打开")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            BrandMark(palette: palette)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
