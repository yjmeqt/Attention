#if DEBUG
import Foundation
import UIKit

/// A reproducible, offline library for exercising Search on the simulator.
enum SearchDemoCorpus {
    private struct Record: Decodable {
        let key: String
        let url: String?
        let site: String
        let title: String
        let authorName: String?
        let authorHandle: String?
        let ocrText: String?
        let visualLabels: [String]
        let keywords: [String]
        let tags: [String]
        let ageHours: Int
        let isArchived: Bool
        let isPrivate: Bool
        let symbol: String?
    }

    @MainActor
    @discardableResult
    static func seed(into library: Library, now: Date = .now) -> Bool {
        guard library.items.isEmpty,
              let url = Bundle.main.url(forResource: "SearchDemoCorpus", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([Record].self, from: data) else { return false }

        for (index, record) in records.enumerated() {
            let itemURL = record.url.flatMap(URL.init(string:))
            let item = LibraryItem(key: record.key, url: itemURL, site: record.site, title: record.title)
            item.authorName = record.authorName
            item.authorHandle = record.authorHandle
            item.ocrText = record.ocrText
            item.visualLabels = record.visualLabels
            item.keywords = record.keywords
            item.tags = record.tags
            item.createdAt = now.addingTimeInterval(TimeInterval(-record.ageHours * 3600))
            item.updatedAt = item.createdAt
            item.isArchived = record.isArchived
            item.isPrivate = record.isPrivate
            if let symbol = record.symbol {
                item.sourceData = symbolImage(symbol, index: index)
                item.thumbnailAspect = 1
            } else {
                item.thumbnailAspect = 0
            }
            library.insertUnsaved(item)
        }
        library.save()
        library.retriedPreviews.formUnion(library.items.map(\.id))
        return true
    }

    private static func symbolImage(_ name: String, index: Int) -> Data? {
        let size = CGSize(width: 512, height: 512)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hue: CGFloat(index % 12) / 12, saturation: 0.55, brightness: 0.72, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let symbol = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 280, weight: .regular))?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            symbol?.draw(in: CGRect(x: 116, y: 116, width: 280, height: 280))
        }
        return image.jpegData(compressionQuality: 0.8)
    }
}
#endif
