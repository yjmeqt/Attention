import SwiftUI

enum AppGroup {
    static let id = "group.com.yijiang.opticshare"
    static let defaults = UserDefaults(suiteName: id) ?? .standard
    static var container: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? URL.applicationSupportDirectory
    }
}

enum Brand {
    static let name = "OpticShare"
}

enum LinkKind: String, Codable {
    case youtube, bilibili, x, web

    init(url: URL) {
        let host = (url.host() ?? "").lowercased()
        func matches(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if matches("youtube.com") || host == "youtu.be" {
            self = .youtube
        } else if matches("bilibili.com") || host == "b23.tv" {
            self = .bilibili
        } else if matches("x.com") || matches("twitter.com") {
            self = .x
        } else {
            self = .web
        }
    }

    var isVideo: Bool { self == .youtube || self == .bilibili }
}

struct LinkMeta: Codable {
    var url: URL
    var site: String
    /// Empty when no preview could be fetched.
    var title: String
    var authorName: String?
    var authorHandle: String?
    var imageData: Data?
    var avatarData: Data?
    var iconData: Data?

    var kind: LinkKind { LinkKind(url: url) }
    var hasPreview: Bool { !title.isEmpty }
    var image: UIImage? { imageData.flatMap(UIImage.init(data:)) }
    var avatar: UIImage? { avatarData.flatMap(UIImage.init(data:)) }
    var icon: UIImage? { iconData.flatMap(UIImage.init(data:)) }

    /// A favicon big enough to show at 64 pt on a 3x card without looking blurry.
    var largeIcon: UIImage? {
        guard let icon, icon.size.width * icon.scale >= 120 else { return nil }
        return icon
    }

    var byline: String? {
        switch (authorName, authorHandle) {
        case let (name?, handle?): "\(name) @\(handle)"
        case let (name?, nil): name
        case let (nil, handle?): "@\(handle)"
        case (nil, nil): nil
        }
    }

    /// Pixel size of the source og:image.
    var imagePixelSize: CGSize? {
        guard let image else { return nil }
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    /// Width ÷ height of the source og:image.
    var imageAspectRatio: CGFloat? {
        guard let size = imagePixelSize, size.height > 0 else { return nil }
        return size.width / size.height
    }

    /// Small or squarish images are usually site logos and look blurry or badly cropped as a banner.
    var imageIsIcon: Bool {
        guard let size = imagePixelSize, let ratio = imageAspectRatio else { return false }
        return size.width < 400 || (ratio < 1.25 && size.width < 640)
    }

    /// The link without tracking parameters; used for the QR code and the clipboard.
    var shareURL: URL { url.cleanedForSharing }

    /// Host and path, for display on the card.
    var displayURL: String {
        let url = shareURL
        var host = url.host() ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let path = url.path(percentEncoded: false)
        return path == "/" ? host : host + path
    }
}

enum CardTemplate: String, Codable, CaseIterable, Identifiable {
    case auto, hero, post, minimal, qr

    var id: Self { self }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .hero: "Image"
        case .post: "Post"
        case .minimal: "Text"
        case .qr: "QR"
        }
    }

    func resolved(for meta: LinkMeta) -> CardTemplate {
        guard self == .auto else { return self }
        guard meta.hasPreview else { return .qr }
        switch meta.kind {
        case .youtube, .bilibili: return .hero
        case .x: return .post
        case .web: return meta.imageData == nil || meta.imageIsIcon ? .minimal : .hero
        }
    }
}

enum CardAspect: String, Codable, CaseIterable, Identifiable {
    case portrait, square, story

    var id: Self { self }

    var label: String {
        switch self {
        case .portrait: "4:5"
        case .square: "1:1"
        case .story: "9:16"
        }
    }

    /// Points; rendered at 3x (1080 px wide).
    var size: CGSize {
        switch self {
        case .portrait: CGSize(width: 360, height: 450)
        case .square: CGSize(width: 360, height: 360)
        case .story: CGSize(width: 360, height: 640)
        }
    }
}

struct CardStyle: Codable, Equatable {
    var template: CardTemplate = .auto
    var aspect: CardAspect = .portrait

    private static let key = "cardStyle"

    static func load() -> CardStyle {
        AppGroup.defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(CardStyle.self, from: $0) } ?? CardStyle()
    }

    func save() {
        AppGroup.defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}

extension CardStyle {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        template = try container.decodeIfPresent(CardTemplate.self, forKey: .template) ?? .auto
        aspect = try container.decodeIfPresent(CardAspect.self, forKey: .aspect) ?? .portrait
    }
}

extension URL {
    static func extract(from text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        return detector?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.url
    }

    private static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "igsh", "igshid", "si", "ref_src", "ref_url",
        "spm_id_from", "from_spmid", "vd_source", "unique_k",
        "share_source", "share_medium", "share_plat", "share_session_id", "share_tag", "share_times",
    ]

    var youTubeID: String? {
        let host = (host() ?? "").lowercased()
        let parts = pathComponents
        if host == "youtu.be" { return parts.count > 1 ? parts[1] : nil }
        if parts.count > 2, ["shorts", "live", "embed"].contains(parts[1]) { return parts[2] }
        return URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "v" }?.value
    }

    var cleanedForSharing: URL {
        switch LinkKind(url: self) {
        case .youtube:
            if let id = youTubeID, let short = URL(string: "https://youtu.be/\(id)") { return short }
            return self
        case .x:
            var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
            components?.query = nil
            components?.fragment = nil
            return components?.url ?? self
        case .bilibili, .web:
            guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
            components.queryItems = components.queryItems?.filter { item in
                let name = item.name.lowercased()
                return !name.hasPrefix("utm_") && !Self.trackingParameters.contains(name)
            }
            if components.queryItems?.isEmpty == true { components.queryItems = nil }
            return components.url ?? self
        }
    }
}
