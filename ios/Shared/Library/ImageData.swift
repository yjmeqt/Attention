import Foundation
import ImageIO
import CryptoKit
import UniformTypeIdentifiers

nonisolated enum ImageData {
    /// Decodes at most `maxPixel` on the long side without loading the full image into memory.
    static func downsample(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func jpeg(_ image: CGImage, quality: Double = 0.85) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// The average color of the image's bottom strip, so a band below it reads as a continuation.
    static func bottomEdgeColor(_ image: CGImage) -> (red: Double, green: Double, blue: Double)? {
        let strip = max(1, image.height / 8)
        guard let edge = image.cropping(to: CGRect(x: 0, y: image.height - strip, width: image.width, height: strip)),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixel = context.data?.assumingMemoryBound(to: UInt8.self)
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(edge, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }

    static func key(for data: Data) -> String {
        "image:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
