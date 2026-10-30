import SwiftUI

#if canImport(UIKit)
import UIKit

typealias PlatformImage = UIImage

extension Image {
    init(platformImage: UIImage) { self.init(uiImage: platformImage) }
}

extension Color {
    /// Behind tiles and grouped content.
    static var secondaryBackground: Color { Color(.secondarySystemBackground) }
}

@MainActor
extension ImageRenderer {
    var platformImage: UIImage? { uiImage }
}
#else
import AppKit

/// The Mac app shares the unfurler and card templates, which were written against `UIImage`.
/// These give `NSImage` the handful of `UIImage` members they use.
typealias PlatformImage = NSImage

nonisolated extension NSImage {
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
    }

    var cgImage: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) }

    /// Pixels per point, so `size * scale` is the pixel size, as on iOS.
    var scale: CGFloat {
        guard size.width > 0, let pixels = representations.map(\.pixelsWide).max(), pixels > 0 else { return 1 }
        return CGFloat(pixels) / size.width
    }

    func pngData() -> Data? { bitmap?.representation(using: .png, properties: [:]) }

    func jpegData(compressionQuality: CGFloat) -> Data? {
        bitmap?.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }

    /// Scaled to fill `size` in pixels, like `UIImage.preparingThumbnail(of:)`.
    func preparingThumbnail(of size: CGSize) -> NSImage? {
        guard let cgImage, size.width >= 1, size.height >= 1,
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let fill = max(size.width / CGFloat(cgImage.width), size.height / CGFloat(cgImage.height))
        let drawn = CGSize(width: CGFloat(cgImage.width) * fill, height: CGFloat(cgImage.height) * fill)
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                                         width: drawn.width, height: drawn.height))
        return context.makeImage().map(NSImage.init(cgImage:))
    }

    private var bitmap: NSBitmapImageRep? {
        cgImage.map(NSBitmapImageRep.init(cgImage:))
    }
}

extension Image {
    init(platformImage: NSImage) { self.init(nsImage: platformImage) }
}

extension Color {
    /// Behind tiles and grouped content.
    static var secondaryBackground: Color { Color(nsColor: .controlBackgroundColor) }
}

@MainActor
extension ImageRenderer {
    /// From `cgImage` rather than `nsImage`, which can come back without a bitmap to copy or save.
    var platformImage: NSImage? {
        cgImage.map { NSImage(cgImage: $0, size: CGSize(width: CGFloat($0.width) / scale, height: CGFloat($0.height) / scale)) }
    }
}
#endif
