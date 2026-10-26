import SwiftUI

struct QRTemplate: View {
    let meta: LinkMeta
    let palette: CardPalette

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                SiteChip(meta: meta, palette: palette)
                Spacer(minLength: 0)
            }
            QRBadge(url: meta.shareURL, size: CardMetrics.bigQRSize, palette: palette, caption: String(localized: "Scan the QR code to open"),
                    logo: meta.largeIcon)
                .padding(.top, 20)
            Text(meta.hasPreview ? meta.title : meta.displayURL)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !meta.hasPreview {
                Text("No preview available. Scan the QR code or paste the link to open it.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            BrandMark(palette: palette)
                .padding(.top, 20)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
    }
}
