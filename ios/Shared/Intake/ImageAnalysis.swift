import Foundation
import Vision

nonisolated enum ImageAnalysis {
    static let person = "person"
    static let portrait = "portrait"

    /// Words people search for that Vision's English labels don't contain.
    static let aliases: [String: [String]] = [
        person: ["人", "人物"],
        portrait: ["人像", "自拍", "肖像"],
    ]

    /// Vision's most confident classifications, plus `person` when there's someone in the image
    /// and `portrait` when a face fills a good part of it.
    @concurrent
    static func labels(for data: Data) async -> [String] {
        guard let image = ImageData.downsample(data, maxPixel: 1024) else { return [] }
        let classified = (try? await ClassifyImageRequest().perform(on: image)) ?? []
        let faces = (try? await DetectFaceRectanglesRequest().perform(on: image)) ?? []
        let humans = (try? await DetectHumanRectanglesRequest().perform(on: image)) ?? []
        var labels = classified
            .filter { $0.confidence >= 0.3 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(8)
            .map(\.identifier)
        let faceHeights = faces.map { $0.boundingBox.cgRect.height }
        if !faceHeights.isEmpty || !humans.isEmpty { labels.append(person) }
        if faceHeights.contains(where: { $0 >= 0.15 }) { labels.append(portrait) }
        return labels
    }
}
