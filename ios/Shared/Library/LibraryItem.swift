import Foundation
import SwiftData

@Model
final class LibraryItem {
    @Attribute(.unique) var id: UUID
    /// Cleaned URL for links, `image:<sha256>` for images.
    @Attribute(.unique) var key: String
    var urlString: String?
    var createdAt: Date
    var updatedAt: Date
    var site: String
    var title: String
    var authorName: String?
    var authorHandle: String?
    var ocrText: String?
    var templateRaw: String
    var aspectRaw: String
    var tags: [String]
    var isPrivate: Bool
    /// Width ÷ height of the thumbnail, so the feed can lay out tiles before loading them.
    var thumbnailAspect: Double

    @MainActor
    init(key: String, url: URL?, site: String, title: String = "", style: CardStyle = CardStyle()) {
        id = UUID()
        self.key = key
        urlString = url?.absoluteString
        createdAt = .now
        updatedAt = .now
        self.site = site
        self.title = title
        templateRaw = style.template.rawValue
        aspectRaw = style.aspect.rawValue
        tags = []
        isPrivate = false
        thumbnailAspect = Double(style.aspect.size.width / style.aspect.size.height)
    }
}

@MainActor
extension LibraryItem {
    var url: URL? { urlString.flatMap(URL.init(string:)) }
    var isImage: Bool { url == nil }

    var style: CardStyle {
        get {
            CardStyle(template: CardTemplate(rawValue: templateRaw) ?? .auto,
                      aspect: CardAspect(rawValue: aspectRaw) ?? .portrait)
        }
        set {
            templateRaw = newValue.template.rawValue
            aspectRaw = newValue.aspect.rawValue
        }
    }

    /// The automatic tag: the normalized domain, or "Images" for image items.
    var domain: String { url.map(DomainTag.domain(of:)) ?? DomainTag.images }
    var domainLabel: String { DomainTag.label(domain) }
    /// The site's own name when known, else its domain.
    var platformName: String { site.isEmpty ? domainLabel : site }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if let url { return LinkMeta(url: url, site: site, title: "").displayURL }
        return createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    func matches(search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [title, urlString ?? "", ocrText ?? "", site].contains { $0.localizedStandardContains(query) }
    }
}

nonisolated enum DomainTag {
    static let images = "Images"

    private static let aliases = [
        "youtu.be": "youtube.com",
        "b23.tv": "bilibili.com",
        "xhslink.com": "xiaohongshu.com",
        "twitter.com": "x.com",
    ]

    static func domain(of url: URL) -> String {
        var host = (url.host() ?? "").lowercased()
        for prefix in ["www.", "m.", "mobile."] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        return aliases[host] ?? host
    }

    @MainActor
    static func label(_ domain: String) -> String {
        domain == images ? String(localized: "Images") : domain
    }

    @MainActor
    static func key(for url: URL) -> String { url.cleanedForSharing.absoluteString }
}
