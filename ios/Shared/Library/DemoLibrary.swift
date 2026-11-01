#if DEBUG
import Foundation
import UIKit

/// Fills an empty library for screenshots: `-demoLinks "https://a https://b"`, newest first.
/// `-demoTags "0=Music,Watch;2=Travel"` tags items by their position in `demoLinks`,
/// `-demoPrivate "10 11"` moves those to Private.
enum DemoLibrary {
    static func run(into library: Library) async {
        guard library.items.isEmpty,
              let links = UserDefaults.standard.string(forKey: "demoLinks") else { return }
        let urls = links.split(separator: " ").compactMap { URL(string: String($0)) }
        let saved: [LibraryItem] = Array(urls.reversed().map { library.save(.link($0, image: nil)) }.reversed())
        // All at once, so the library is ready before the screenshot is taken.
        let enriching = saved.map { item in Task { _ = await library.enrich(item) } }
        for task in enriching { await task.value }
        // With thirty at once a few time out; retry those here, so the app's own retry later
        // doesn't bump them to the top and shuffle the order the screenshots rely on.
        for _ in 0..<2 {
            for item in saved where item.title.isEmpty && library.data(.cover, of: item) == nil { _ = await library.enrich(item) }
        }
        library.retriedPreviews.formUnion(saved.map(\.id))
        // Enriching bumps each item to the top; restore the demoLinks order, a few minutes apart.
        for (index, item) in saved.enumerated() { item.updatedAt = .now.addingTimeInterval(Double(index) * -420) }
        library.save()
        for entry in (UserDefaults.standard.string(forKey: "demoTags") ?? "").split(separator: ";") {
            let parts = entry.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let index = Int(parts[0]), saved.indices.contains(index) else { continue }
            for tag in parts[1].split(separator: ",") { library.addTag(String(tag), to: [saved[index]]) }
        }
        let hidden = (UserDefaults.standard.string(forKey: "demoPrivate") ?? "").split(separator: " ")
            .compactMap { Int($0) }.filter(saved.indices.contains).map { saved[$0] }
        if !hidden.isEmpty { library.setPrivate(true, hidden) }
        // Tells the screenshot script the library is in place.
        try? Data().write(to: URL.documentsDirectory.appending(path: "demo-ready"))
    }

    /// `-demoBulk 5000` fills an empty library with that many offline items for performance work:
    /// covers cycle through a pool of generated images across the tile aspect range, every fifth has none.
    static func bulk(into library: Library) {
        let count = UserDefaults.standard.integer(forKey: "demoBulk")
        guard count > 0, library.items.isEmpty else { return }
        let sites = [("github.com", "GitHub"), ("www.youtube.com", "YouTube"), ("en.wikipedia.org", "Wikipedia"),
                     ("sspai.com", "少数派"), ("x.com", "X"), ("www.reddit.com", "Reddit"),
                     ("www.bilibili.com", "bilibili"), ("medium.com", "Medium")]
        let words = ["Swift", "concurrency", "layout", "The", "Great", "Wall", "of", "China", "高效工作", "品质生活",
                     "composable", "architecture", "Never", "Gonna", "Give", "You", "Up", "testing", "a", "modern",
                     "expressive", "package", "for", "performance", "collection", "view", "diffable", "data", "source"]
        let pool = (0..<48).map { index -> (cover: Data, tile: Data, aspect: Double)? in
            let aspect = Library.tileAspects.lowerBound
                + (Library.tileAspects.upperBound - Library.tileAspects.lowerBound) * Double(index) / 47
            let size = CGSize(width: 1200, height: (1200 / aspect).rounded())
            let image = UIGraphicsImageRenderer(size: size, format: .init(for: .init(displayScale: 1))).image { context in
                let hue = CGFloat(index) / 48
                let colors = [UIColor(hue: hue, saturation: 0.6, brightness: 0.9, alpha: 1).cgColor,
                              UIColor(hue: hue + 0.15, saturation: 0.8, brightness: 0.4, alpha: 1).cgColor]
                let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: nil)!
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
                for ring in 0..<12 {
                    UIColor(white: 1, alpha: 0.08).setFill()
                    let side = CGFloat(ring) * size.width / 10
                    UIBezierPath(ovalIn: CGRect(x: CGFloat(ring * 70), y: CGFloat(ring * 37), width: side, height: side)).fill()
                }
                ("#\(index)" as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 160, weight: .black), .foregroundColor: UIColor.white,
                ])
            }
            guard let cgImage = image.cgImage, let cover = ImageData.jpeg(cgImage),
                  let tileImage = ImageData.downsample(cover, maxPixel: 720),
                  let tile = UIImage(cgImage: tileImage).jpegData(compressionQuality: 0.8) else { return nil }
            return (cover, tile, Double(tileImage.width) / Double(tileImage.height))
        }
        var generator = SystemRandomNumberGenerator()
        for index in 0..<count {
            let (host, site) = sites[index % sites.count]
            let url = URL(string: "https://\(host)/bulk/\(index)")!
            let title = (0..<Int.random(in: 2...16, using: &generator)).map { _ in words.randomElement(using: &generator)! }
                .joined(separator: " ")
            let item = LibraryItem(key: url.absoluteString, url: url, site: site, title: "\(index) \(title)")
            item.updatedAt = .now.addingTimeInterval(Double(index) * -90)
            item.createdAt = item.updatedAt
            library.insertUnsaved(item)
            if index % 5 != 4, let image = pool[index % pool.count] {
                library.write(image.cover, .cover, of: item)
                library.write(image.tile, .thumbnail, of: item)
                item.thumbnailAspect = image.aspect
            } else {
                item.thumbnailAspect = 0
            }
        }
        library.save()
        try? Data().write(to: URL.documentsDirectory.appending(path: "demo-ready"))
    }

    /// `-demoOpen 0` opens that item, `-demoSearch text` fills the search field, `-demoTagFilter Music` turns a tag on.
    static var open: Int? { UserDefaults.standard.object(forKey: "demoOpen") != nil ? UserDefaults.standard.integer(forKey: "demoOpen") : nil }
    static var search: String? { UserDefaults.standard.string(forKey: "demoSearch") }
    static var tagFilter: String? { UserDefaults.standard.string(forKey: "demoTagFilter") }
    /// `-demoUnlockPrivate YES` opens Private, still locked, and asks for Face ID.
    static var unlocksPrivate: Bool { UserDefaults.standard.bool(forKey: "demoUnlockPrivate") }
}
#endif
