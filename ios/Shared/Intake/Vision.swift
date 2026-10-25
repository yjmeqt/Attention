import Foundation
import Vision
import CoreImage

nonisolated enum QRReader {
    /// Payloads of every QR code in the image, top to bottom.
    static func payloads(in image: CGImage) async -> [String] {
        var request = DetectBarcodesRequest()
        request.symbologies = [.qr]
        let results = (try? await request.perform(on: image)) ?? []
        let payloads = results
            .sorted { $0.boundingBox.cgRect.maxY > $1.boundingBox.cgRect.maxY }
            .compactMap(\.payloadString)
        return payloads.isEmpty ? coreImagePayloads(in: image) : payloads
    }

    /// Vision's barcode detector finds nothing in the Simulator and on some older devices.
    private static func coreImagePayloads(in image: CGImage) -> [String] {
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return (detector?.features(in: CIImage(cgImage: image)) ?? [])
            .compactMap { $0 as? CIQRCodeFeature }
            .sorted { $0.bounds.maxY > $1.bounds.maxY }
            .compactMap(\.messageString)
    }

    static func firstWebLink(in image: CGImage) async -> URL? {
        for payload in await payloads(in: image) {
            if let url = URL.extract(from: payload), url.scheme?.hasPrefix("http") == true { return url }
        }
        return nil
    }
}

nonisolated enum TextReader {
    struct Line: Equatable {
        var text: String
        /// Normalized line height; bigger type means a bigger value.
        var height: Double
        /// Normalized distance from the top of the image to the top of the line.
        var top: Double
    }

    struct Result: Equatable {
        var title: String?
        var fullText: String
    }

    static func read(_ data: Data) async -> Result? {
        guard let image = ImageData.downsample(data, maxPixel: 2048) else { return nil }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        guard let observations = try? await request.perform(on: image) else { return nil }
        let lines = observations.compactMap { observation -> Line? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox.cgRect
            return Line(text: text, height: box.height, top: 1 - box.maxY)
        }
        guard !lines.isEmpty else { return nil }
        let full = lines.sorted { $0.top < $1.top }.map(\.text).joined(separator: "\n")
        return Result(title: title(from: lines), fullText: full)
    }

    private static let boilerplate = [
        "小红书", "扫码", "扫一扫", "长按", "二维码", "打开App", "打开app", "查看笔记", "查看更多",
        "xiaohongshu", "Scan", "QR code", "rednote", "REDnote",
    ]

    /// The 1–2 lines with the biggest type in the top 60% of the image, skipping app boilerplate.
    static func title(from lines: [Line]) -> String? {
        let candidates = lines.filter { line in
            let text = line.text.trimmingCharacters(in: .whitespaces)
            return line.top < 0.6
                && text.count >= 2
                && !text.hasPrefix("@")
                && text.contains(where: \.isLetter)
                && !boilerplate.contains { text.localizedCaseInsensitiveContains($0) }
        }
        guard let tallest = candidates.map(\.height).max() else { return nil }
        let big = candidates.filter { $0.height >= tallest * 0.8 }.sorted { $0.top < $1.top }
        guard let first = big.first else { return nil }
        var picked = [first]
        if big.count > 1, big[1].top - (first.top + first.height) < first.height * 1.5 { picked.append(big[1]) }
        let joinsTight = picked.contains { $0.text.unicodeScalars.contains { $0.properties.isIdeographic } }
        let title = picked.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: joinsTight ? "" : " ")
        return String(title.prefix(80))
    }
}
