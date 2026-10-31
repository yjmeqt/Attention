import Foundation
import SwiftData

/// Synced through CloudKit, which rules out unique attributes and needs a default for every property.
/// `Library` merges the duplicates two devices can create for the same `key`.
@Model
final class LibraryItem {
    var id = UUID()
    /// Cleaned URL for links, `image:<sha256>` for images.
    var key = ""
    var urlString: String?
    var createdAt = Date.now
    var updatedAt = Date.now
    var site = ""
    var title = ""
    var authorName: String?
    var authorHandle: String?
    var ocrText: String?
    var templateRaw = CardTemplate.auto.rawValue
    var tags: [String] = []
    var isPrivate = false
    /// Hidden from the feed but kept, unlike deleted items.
    var isArchived = false
    /// For links shared as an image: show that image instead of the link's preview image.
    var usesSharedImage = false
    /// Show the image the user picked; wins over `usesSharedImage`, which older versions still read.
    var usesCustomImage = false
    /// Width ÷ height of the thumbnail, so the feed can lay out tiles before loading them.
    var thumbnailAspect = 0.8

    // Images live outside the database and sync as CloudKit assets. Read and write them through `Library`.
    /// The link's preview image.
    @Attribute(.externalStorage) var coverData: Data?
    @Attribute(.externalStorage) var avatarData: Data?
    @Attribute(.externalStorage) var iconData: Data?
    /// The image the item was shared or pasted as.
    @Attribute(.externalStorage) var sourceData: Data?
    /// An image the user picked for a link's card.
    @Attribute(.externalStorage) var customData: Data?

    @MainActor
    init(key: String, url: URL?, site: String, title: String = "", style: CardStyle = CardStyle()) {
        self.key = key
        urlString = url?.absoluteString
        self.site = site
        self.title = title
        templateRaw = style.template.rawValue
    }
}

@MainActor
extension LibraryItem {
    var url: URL? { urlString.flatMap(URL.init(string:)) }
    var isImage: Bool { url == nil }

    var style: CardStyle {
        get { CardStyle(template: CardTemplate(rawValue: templateRaw) ?? .auto) }
        set { templateRaw = newValue.template.rawValue }
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
