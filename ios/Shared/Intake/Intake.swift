import Foundation
import UIKit
import UniformTypeIdentifiers

/// Something shared into or pasted into OpticShare, before it's saved.
enum Capture: Equatable {
    /// A link; `image` is the shared image it was read from, if any.
    case link(URL, image: Data?)
    case image(Data)
}

enum Intake {
    /// Shared images are kept at most this big on the long side.
    private static let maxImagePixel = 2048

    static func capture(from items: [NSExtensionItem]) async -> Capture? {
        let providers = items.flatMap { $0.attachments ?? [] }
        let image = await ItemProviders.firstImage(in: providers)
        let link = await ItemProviders.firstLink(in: items, skippingImages: true)
        return await capture(image: image, link: link)
    }

    static func capture(from providers: [NSItemProvider]) async -> Capture? {
        let image = await ItemProviders.firstImage(in: providers)
        let link = await ItemProviders.firstLink(in: providers, skippingImages: true)
        return await capture(image: image, link: link)
    }

    static func capture(image data: Data?, link: URL?) async -> Capture? {
        guard let data, let cgImage = ImageData.downsample(data, maxPixel: maxImagePixel),
              let normalized = ImageData.jpeg(cgImage) else {
            return link.map { .link($0, image: nil) }
        }
        if let qr = await QRReader.firstWebLink(in: cgImage) { return .link(qr, image: normalized) }
        if let link { return .link(link, image: normalized) }
        return .image(normalized)
    }
}

extension Library {
    /// Saves a capture right away so nothing is lost if the share extension is closed early.
    func save(_ capture: Capture) -> LibraryItem {
        switch capture {
        case let .link(url, image):
            let item = upsert(key: DomainTag.key(for: url), url: url, site: Unfurler.siteName(url), style: CardStyle.load())
            if let image { write(image, .source, of: item) }
            if data(.thumbnail, of: item) == nil { refreshThumbnail(item) }
            save()
            return item
        case let .image(data):
            let item = upsert(key: ImageData.key(for: data), url: nil, site: "", style: CardStyle.load())
            write(data, .source, of: item)
            refreshThumbnail(item)
            save()
            return item
        }
    }

    /// Fetches the link preview and reads text from the shared image, updating the saved item.
    /// Returns a notice to show when only a basic card could be made.
    @discardableResult
    func enrich(_ item: LibraryItem) async -> String? {
        enriching.insert(item.id)
        defer { enriching.remove(item.id) }
        let source = data(.source, of: item)
        async let text: TextReader.Result? = if let source { await TextReader.read(source) } else { nil }
        guard let url = item.url else {
            let result = await text
            item.title = result?.title ?? ""
            item.ocrText = result?.fullText
            save()
            return nil
        }
        let result = await Unfurler.unfurlWithFallback(url)
        let read = await text
        item.ocrText = read?.fullText
        var meta = result.meta
        if meta.imageData == nil || meta.imageIsIcon, let source { meta.imageData = source }
        if !meta.hasPreview, let title = read?.title { meta.title = title }
        if result.isFallback, !item.title.isEmpty, data(.cover, of: item) != nil {
            save()
            return nil
        }
        setMeta(meta, for: item)
        return result.isFallback && !meta.hasPreview
            ? String(localized: "Couldn't load a preview, so this is a basic card.") : nil
    }
}
