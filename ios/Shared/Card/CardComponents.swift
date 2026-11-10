import SwiftUI
import CoreImage.CIFilterBuiltins

enum QRCode {
    private static var cache: [String: PlatformImage] = [:]
    private static let context = CIContext()

    /// Use `H` (30% recovery) when a logo covers the center.
    static func image(_ string: String, correctionLevel: String = "M") -> PlatformImage {
        let key = correctionLevel + string
        if let cached = cache[key] { return cached }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = correctionLevel
        let output = filter.outputImage!.transformed(by: .init(scaleX: 10, y: 10))
        let image = PlatformImage(cgImage: context.createCGImage(output, from: output.extent)!)
        cache[key] = image
        return image
    }
}

struct SiteChip: View {
    let meta: LinkMeta
    let palette: CardPalette

    private var label: String {
        switch meta.kind {
        case .youtube: String(localized: "YouTube · Video")
        case .bilibili: String(localized: "Bilibili · Video")
        case .x: String(localized: "X · Post")
        case .web: meta.site.count > 18 ? String(meta.site.prefix(17)) + "…" : meta.site
        }
    }

    /// Shown at 14 pt (42 px); smaller favicons would look blurry.
    private var icon: PlatformImage? {
        guard let icon = meta.icon, icon.size.width * icon.scale >= 32 else { return nil }
        return icon
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(platformImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .padding(2)
                    .background(.white, in: .rect(cornerRadius: 4))
            }
            Text(verbatim: label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.onAccent)
                .lineLimit(1)
        }
        .padding(.leading, icon == nil ? 10 : 4)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(palette.accent, in: .capsule)
    }
}

struct QRBadge: View {
    let url: URL
    let size: CGFloat
    let palette: CardPalette
    var caption = String(localized: "Scan to open")
    var logo: PlatformImage?

    var body: some View {
        VStack(spacing: 5) {
            Image(platformImage: QRCode.image(url.absoluteString, correctionLevel: logo == nil ? "M" : "H"))
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
                .overlay {
                    if let logo {
                        Image(platformImage: logo)
                            .resizable()
                            .scaledToFit()
                            .frame(width: size * 0.18, height: size * 0.18)
                            .padding(size * 0.025)
                            .background(.white, in: .rect(cornerRadius: size * 0.04))
                    }
                }
                .padding(6)
                .background(.white, in: .rect(cornerRadius: 8))
            Text(verbatim: caption)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondary)
        }
    }
}

struct BrandMark: View {
    let palette: CardPalette

    var body: some View {
        Text("Made with \(Brand.name)")
            .font(.system(size: 11))
            .foregroundStyle(palette.tertiary)
    }
}

struct CardFooter: View {
    let meta: LinkMeta
    let palette: CardPalette
    let qrSize: CGFloat?

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: meta.displayURL)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                BrandMark(palette: palette)
            }
            Spacer(minLength: 0)
            if let qrSize {
                QRBadge(url: meta.shareURL, size: qrSize, palette: palette)
            }
        }
    }
}

/// Shared branding and QR layout for image tiles and saved-text cards.
struct BrandedCardFooter: View {
    let tint: CardTint
    var displayURL: String?
    var qrURL: URL?

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if let displayURL {
                    Text(verbatim: displayURL)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tint.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 6) {
                    AttentionGlyph(size: 18)
                    Text("Made with \(Brand.name)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint.secondary)
                }
            }
            Spacer(minLength: 0)
            if let qrURL {
                Image(platformImage: QRCode.image(qrURL.absoluteString))
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 60, height: 60)
                    .padding(5)
                    .background(.white, in: .rect(cornerRadius: 9, style: .continuous))
            }
        }
    }
}

/// Site icon for in-app lists, with a link glyph when there's no favicon.
struct FaviconView: View {
    let meta: LinkMeta
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let icon = meta.icon {
                Image(platformImage: icon).resizable().scaledToFit().padding(size * 0.12)
            } else {
                Image(systemName: "link").font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(.fill.quaternary, in: .rect(cornerRadius: size * 0.25))
        .accessibilityHidden(true)
    }
}

struct PlayGlyph: View {
    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 60, height: 60)
            .background(.black.opacity(0.55), in: .circle)
    }
}

/// The app icon in miniature: a two-tone chat bubble on the brand red, the same artwork as App/Attention.icon.
struct AttentionGlyph: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(Color(red: 0.910, green: 0.251, blue: 0.165))
            .overlay {
                IconBubble(part: .bubble).fill(Color(red: 0.965, green: 0.953, blue: 0.929))
                IconBubble(part: .cover).fill(Color(red: 0.082, green: 0.082, blue: 0.102))
            }
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(.black.opacity(0.08), lineWidth: 0.5)
            }
    }
}

/// The icon's bubble and its dark cover block, in the icon's 1024-unit space.
nonisolated struct IconBubble: Shape {
    enum Part { case bubble, cover }
    let part: Part

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1024
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(312, 176))
        path.addLine(to: p(712, 176))
        path.addCurve(to: p(876, 340), control1: p(804, 176), control2: p(876, 248))
        switch part {
        case .cover:
            path.addLine(to: p(876, 520))
            path.addLine(to: p(148, 520))
        case .bubble:
            path.addLine(to: p(876, 684))
            path.addCurve(to: p(712, 848), control1: p(876, 776), control2: p(804, 848))
            path.addLine(to: p(452, 848))
            path.addLine(to: p(316, 956))
            path.addCurve(to: p(268, 932), control1: p(296, 972), control2: p(268, 958))
            path.addLine(to: p(268, 836))
            path.addCurve(to: p(148, 684), control1: p(206, 810), control2: p(148, 746))
        }
        path.addLine(to: p(148, 340))
        path.addCurve(to: p(312, 176), control1: p(148, 248), control2: p(220, 176))
        path.closeSubpath()
        return path
    }
}
