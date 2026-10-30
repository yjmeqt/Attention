import SwiftUI

/// Looks like the feed tile: the photo close to its own shape, its color carried into the text,
/// and a QR code where the tile has its Open button.
struct TileTemplate: View {
    let meta: LinkMeta

    static let width: CGFloat = 360
    private static let padding: CGFloat = 18

    /// Image height ÷ width, kept between 16:9 and 9:16. Nil when there's no photo to show.
    static func imageRatio(_ meta: LinkMeta) -> CGFloat? {
        guard let size = meta.imagePixelSize, let ratio = meta.imageAspectRatio, ratio > 0 else { return nil }
        let isIcon = max(size.width, size.height) < 400 || ((0.8...1.25).contains(ratio) && size.width < 640)
        guard !isIcon else { return nil }
        return min(max(1 / ratio, 9.0 / 16), 16.0 / 9)
    }

    var body: some View {
        Group {
            if let image = meta.image, let ratio = Self.imageRatio(meta) {
                let tint = CardTint(image) ?? .neutral
                let photo = Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.width, height: Self.width * ratio)
                    .clipped()
                if ratio > 1 {
                    photo.overlay(alignment: .bottom) {
                        info(tint, titleLines: 4)
                            .background(alignment: .bottom) { scrim(tint) }
                    }
                } else {
                    VStack(spacing: 0) {
                        photo
                        info(tint, titleLines: 4).background(tint.color)
                    }
                }
            } else {
                textOnly
            }
        }
        .frame(width: Self.width)
        .overlay {
            if meta.kind.isVideo, meta.image != nil { PlayGlyph() }
        }
    }

    /// Fades the photo into the band color so the text reads like it's on the band.
    private func scrim(_ tint: CardTint) -> some View {
        LinearGradient(stops: [
            .init(color: tint.color.opacity(0), location: 0),
            .init(color: tint.color.opacity(0.75), location: 0.35),
            .init(color: tint.color, location: 0.7),
        ], startPoint: .top, endPoint: .bottom)
        .padding(.top, -90)
    }

    private func info(_ tint: CardTint, titleLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                eyebrow(tint, iconSize: 16)
                Text(verbatim: meta.title)
                    .font(.system(size: titleSize(lines: 1), weight: .bold))
                    .lineSpacing(1)
                    .lineLimit(titleLines)
                    .minimumScaleFactor(0.85)
                if let byline = meta.byline {
                    Text(verbatim: byline)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tint.secondary)
                        .lineLimit(1)
                }
            }
            footer(tint)
        }
        .foregroundStyle(tint.primary)
        .padding(Self.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var textOnly: some View {
        let tint = meta.icon.flatMap(CardTint.init(favicon:)) ?? .neutral
        return VStack(alignment: .leading, spacing: 0) {
            eyebrow(tint, iconSize: 16)
            Text(verbatim: meta.title)
                .font(.system(size: titleSize(lines: 2), weight: meta.kind == .x ? .medium : .bold))
                .lineSpacing(3)
                .lineLimit(12)
                .minimumScaleFactor(0.8)
                .padding(.top, 10)
            if let byline = meta.byline {
                Text(verbatim: byline)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint.secondary)
                    .lineLimit(1)
                    .padding(.top, 8)
            }
            Spacer(minLength: 28)
            footer(tint)
        }
        .foregroundStyle(tint.primary)
        .padding(Self.padding + 4)
        .frame(width: Self.width, alignment: .leading)
        .frame(minHeight: Self.width * 0.8, alignment: .topLeading)
        .background(tint.color)
    }

    /// Shorter titles get bigger type; `lines` raises the size for cards with nothing but text.
    private func titleSize(lines: Int) -> CGFloat {
        let length = meta.title.unicodeScalars.reduce(0) { $0 + ($1.value > 0x2E80 ? 2 : 1) }
        let base: CGFloat = length <= 30 ? 26 : length <= 70 ? 22 : 19
        return lines > 1 ? base + 1 : base
    }

    private func eyebrow(_ tint: CardTint, iconSize: CGFloat) -> some View {
        HStack(spacing: 6) {
            favicon(size: iconSize)
            Text(verbatim: meta.kind == .x ? "X" : meta.site)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(tint.secondary)
    }

    private func favicon(size: CGFloat) -> some View {
        Group {
            if let icon = meta.icon {
                Image(platformImage: icon).resizable().scaledToFit().padding(size * 0.12)
            } else {
                Image(systemName: "globe").font(.system(size: size * 0.55)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(.white, in: .rect(cornerRadius: size * 0.24, style: .continuous))
    }

    private func footer(_ tint: CardTint) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: meta.displayURL)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    AttentionGlyph(size: 18)
                    Text("Made with \(Brand.name)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(platformImage: QRCode.image(meta.shareURL.absoluteString))
                .interpolation(.none)
                .resizable()
                .frame(width: 60, height: 60)
                .padding(5)
                .background(.white, in: .rect(cornerRadius: 9, style: .continuous))
        }
    }
}

/// A card's band color and the text colors that read on it.
struct CardTint {
    let color: Color
    let isDark: Bool

    static let neutral = CardTint(color: Color(red: 0.95, green: 0.95, blue: 0.96), isDark: false)

    var primary: Color { isDark ? .white : Color(red: 0.07, green: 0.07, blue: 0.08) }
    var secondary: Color { primary.opacity(isDark ? 0.72 : 0.6) }

    /// From the image's bottom edge, like the feed.
    init?(_ image: PlatformImage) {
        guard let cgImage = image.cgImage, let rgb = ImageData.bottomEdgeColor(cgImage) else { return nil }
        color = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        isDark = 0.299 * rgb.red + 0.587 * rgb.green + 0.114 * rgb.blue < 0.6
    }

    /// Colorful favicons tint the card; black, white and gray ones would make it a slab, so they don't.
    init?(favicon: PlatformImage) {
        guard let cgImage = favicon.cgImage, let rgb = ImageData.averageColor(cgImage) else { return nil }
        let high = max(rgb.red, rgb.green, rgb.blue), low = min(rgb.red, rgb.green, rgb.blue)
        guard high > 0.15, (high - low) / high > 0.35 else { return nil }
        color = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        isDark = 0.299 * rgb.red + 0.587 * rgb.green + 0.114 * rgb.blue < 0.6
    }

    init(color: Color, isDark: Bool) {
        self.color = color
        self.isDark = isDark
    }
}
