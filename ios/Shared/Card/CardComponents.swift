import SwiftUI
import CoreImage.CIFilterBuiltins

enum QRCode {
    private static var cache: [String: UIImage] = [:]
    private static let context = CIContext()

    /// Use `H` (30% recovery) when a logo covers the center.
    static func image(_ string: String, correctionLevel: String = "M") -> UIImage {
        let key = correctionLevel + string
        if let cached = cache[key] { return cached }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = correctionLevel
        let output = filter.outputImage!.transformed(by: .init(scaleX: 10, y: 10))
        let image = UIImage(cgImage: context.createCGImage(output, from: output.extent)!)
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
    private var icon: UIImage? {
        guard let icon = meta.icon, icon.size.width * icon.scale >= 32 else { return nil }
        return icon
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(uiImage: icon)
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
    var logo: UIImage?

    var body: some View {
        VStack(spacing: 5) {
            Image(uiImage: QRCode.image(url.absoluteString, correctionLevel: logo == nil ? "M" : "H"))
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
                .overlay {
                    if let logo {
                        Image(uiImage: logo)
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

struct HeroImage: View {
    let meta: LinkMeta
    let palette: CardPalette
    let size: CGSize

    /// Images much narrower than the banner (logos, portrait photos) are shown whole over a blurred fill instead of being cropped.
    private var fitsInside: Bool {
        guard let ratio = meta.imageAspectRatio, size.height > 0 else { return false }
        return ratio < size.width / size.height * 0.75
    }

    var body: some View {
        if let image = meta.image {
            if fitsInside {
                ZStack {
                    Image(uiImage: image).resizable().scaledToFill()
                        .blur(radius: 24, opaque: true)
                        .overlay(.black.opacity(0.15))
                    Image(uiImage: image).resizable().scaledToFit()
                }
                .frame(width: size.width, height: size.height)
                .clipped()
            } else {
                Image(uiImage: image).resizable().scaledToFill()
            }
        } else {
            ZStack {
                LinearGradient(colors: [palette.accent, palette.accent.opacity(0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 10) {
                    if let icon = meta.largeIcon {
                        Image(uiImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .padding(8)
                            .background(.white, in: .rect(cornerRadius: 18))
                    }
                    Text(verbatim: meta.site)
                        .font(.system(size: meta.largeIcon == nil ? 40 : 24, weight: .bold))
                        .foregroundStyle(palette.onAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }
                .padding()
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
                Image(uiImage: icon).resizable().scaledToFit().padding(size * 0.12)
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

struct Avatar: View {
    let meta: LinkMeta
    let palette: CardPalette

    var body: some View {
        if let avatar = meta.avatar {
            Image(uiImage: avatar).resizable().scaledToFill().clipShape(.circle)
        } else {
            Circle().fill(palette.accent).overlay {
                Text(verbatim: String((meta.authorName ?? meta.site).prefix(1)).uppercased())
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(palette.onAccent)
            }
        }
    }
}
