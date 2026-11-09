import Foundation
import CryptoKit
import UniformTypeIdentifiers

/// Something shared into or pasted into Attention, before it's saved.
struct Capture: Equatable {
    var url: URL?
    var image: Data?
    var text: String?

    init(url: URL? = nil, image: Data? = nil, text: String? = nil) {
        self.url = url
        self.image = image
        self.text = text.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    static func link(_ url: URL, image: Data?) -> Capture { Capture(url: url, image: image) }
    static func image(_ data: Data) -> Capture { Capture(image: data) }

    /// Versioned, length-delimited fields prevent ambiguous concatenations and preserve exact body bytes.
    var key: String {
        guard let text else {
            return url.map { DomainTag.key(for: $0.upgradedToHTTPS) } ?? ImageData.key(for: image ?? Data())
        }
        var encoded = Data("capture-v1".utf8)
        for value in [text, url.map { DomainTag.key(for: $0.upgradedToHTTPS) }, image.map { ImageData.key(for: $0) }] {
            if let value {
                let bytes = Data(value.utf8)
                encoded.append(Data("\(bytes.count):".utf8))
                encoded.append(bytes)
            } else {
                encoded.append(Data("-:".utf8))
            }
        }
        return "text:v1:" + SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
    }
}

enum Intake {
    static let maxImagePixel = 2048

    static func capture(from items: [NSExtensionItem]) async -> Capture? {
        let providers = items.flatMap { $0.attachments ?? [] }
        var texts: [String] = []
        for item in items {
            // The content is a fallback for hosts that don't expose a body attachment.
            let attached = await ItemProviders.plainTexts(in: item.attachments ?? [])
            texts.append(contentsOf: attached)
            if !attached.contains(where: { ItemProviders.standaloneWebURL(in: $0) == nil }),
               let text = item.attributedContentText?.string,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !attached.contains(text) {
                texts.append(text)
            }
        }
        let result = await capture(providers: providers, texts: texts)
        if texts.isEmpty, result?.url == nil,
           let titleLink = items.compactMap({ $0.attributedTitle?.string }).compactMap({ ItemProviders.standaloneWebURL(in: $0) }).first {
            return Capture(url: titleLink, image: result?.image)
        }
        return result
    }

    static func capture(from providers: [NSItemProvider]) async -> Capture? {
        await capture(providers: providers, texts: ItemProviders.plainTexts(in: providers))
    }

    private static func capture(providers: [NSItemProvider], texts: [String]) async -> Capture? {
        let explicit = await ItemProviders.explicitLink(in: providers)
        let standaloneURLs = texts.compactMap { ItemProviders.standaloneWebURL(in: $0) }
        let multipleURLBodies = standaloneURLs.count == texts.count && Set(standaloneURLs).count > 1
        let standalone = texts.count == 1 ? standaloneURLs.first : nil
        let link = if multipleURLBodies { nil as URL? }
            else if let known = explicit ?? standalone { known }
            else if texts.isEmpty { await ItemProviders.standaloneLink(in: providers) }
            else { nil as URL? }
        let bodies = texts.filter { text in
            guard let standalone = ItemProviders.standaloneWebURL(in: text) else { return true }
            return standalone != link
        }
        let image = await ItemProviders.firstImage(in: providers)
        return await capture(image: image, link: link, text: bodies.isEmpty ? nil : bodies.joined(separator: "\n\n"))
    }

    static func capture(image data: Data?, link: URL?, text: String? = nil) async -> Capture? {
        var result = Capture(url: link, text: text)
        if let data, let cgImage = ImageData.downsample(data, maxPixel: maxImagePixel),
           let normalized = ImageData.jpeg(cgImage) {
            result.image = normalized
            if let qr = await QRReader.firstWebLink(in: cgImage) { result.url = qr }
        }
        return result.url != nil || result.image != nil || result.text != nil ? result : nil
    }
}

extension Library {
    /// Saves a capture right away so nothing is lost if the share extension is closed early.
    @discardableResult
    func save(_ capture: Capture) -> LibraryItem {
        let url = capture.url?.upgradedToHTTPS
        let item = upsert(key: capture.key, url: url, site: url.map(Unfurler.siteName) ?? "", style: CardStyle.load())
        if let text = capture.text { item.text = text }
        if let image = capture.image { write(image, .source, of: item) }
        if data(.thumbnail, of: item) == nil { refreshThumbnail(item) }
        save()
        return item
    }

    /// Retries links saved without a preview, e.g. when the share extension closed before the page
    /// loaded. Each item is retried once per launch so pages that never preview don't refetch forever.
    func retryMissingPreviews(fetchPreview: (URL) async -> Unfurler.Result = Unfurler.unfurlWithFallback) async {
        let stale = items.filter {
            $0.url != nil && $0.title.isEmpty && data(.cover, of: $0) == nil
                && !enriching.contains($0.id) && retriedPreviews.insert($0.id).inserted
        }
        for item in stale.prefix(20) {
            guard !Task.isCancelled else { return }
            guard contains(item) else { continue }
            if let url = item.url, url.upgradedToHTTPS != url {
                let key = Capture(url: url.upgradedToHTTPS, image: data(.source, of: item), text: item.text).key
                if self.item(forKey: key).map({ $0.id == item.id }) ?? true {
                    item.urlString = url.upgradedToHTTPS.absoluteString
                    item.key = key
                    save()
                }
            }
            _ = await enrich(item, fetchPreview: fetchPreview)
        }
        #if !SHARE_EXTENSION
        await analyzePending()
        #endif
    }

    /// Fetches the link preview and reads text from the shared image, updating the saved item.
    /// Returns a notice to show when only a basic card could be made.
    @discardableResult
    func enrich(_ item: LibraryItem,
                fetchPreview: (URL) async -> Unfurler.Result = Unfurler.unfurlWithFallback,
                readText: @Sendable (Data) async -> TextReader.Result? = TextReader.read) async -> String? {
        guard !Task.isCancelled, contains(item) else { return nil }
        let id = item.id
        guard enriching.insert(id).inserted else { return nil }
        defer {
            enriching.remove(id)
            if !Task.isCancelled, contains(item) {
                invalidateAnalysis(item)
                save()
            }
        }
        let source = data(.source, of: item)
        guard item.url != nil || source != nil else { return nil }
        async let text: TextReader.Result? = if let source { await readText(source) } else { nil }
        guard let url = item.url else {
            let result = await text
            guard !Task.isCancelled, contains(item) else { return nil }
            item.title = result?.title ?? ""
            item.ocrText = result?.fullText
            save()
            return nil
        }
        let result = await fetchPreview(url)
        let read = await text
        guard !Task.isCancelled, contains(item) else { return nil }
        item.ocrText = read?.fullText
        var meta = result.meta
        if let read {
            item.ocrText = read.fullText
        } else if let cover = meta.imageData, !meta.imageIsIcon {
            let coverText = await readText(cover)
            guard !Task.isCancelled, contains(item) else { return nil }
            item.ocrText = coverText?.fullText
        } else {
            item.ocrText = nil
        }
        // On the first fetch, a link with no usable preview image starts out showing the image it was shared as.
        if meta.imageData == nil || meta.imageIsIcon, source != nil, item.title.isEmpty, !item.usesCustomImage {
            item.usesSharedImage = true
        }
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
