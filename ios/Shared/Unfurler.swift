import SwiftUI
import LinkPresentation
import UniformTypeIdentifiers

enum Unfurler {
    struct Result {
        var meta: LinkMeta
        var isFallback: Bool
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    static func unfurlWithFallback(_ url: URL) async -> Result {
        let url = url.upgradedToHTTPS
        async let originIcon = favicon(near: url)
        async let googleIcon = googleFavicon(url)
        var result = await unfurl(url)
        var icon = result.meta.iconData
        if icon == nil { icon = await originIcon }
        if pixelWidth(icon) < 64, let better = await googleIcon, pixelWidth(better) > pixelWidth(icon) { icon = better }
        result.meta.iconData = icon
        return result
    }

    private static func pixelWidth(_ data: Data?) -> CGFloat {
        guard let data, let image = PlatformImage(data: data) else { return 0 }
        return image.size.width * image.scale
    }

    private static func unfurl(_ url: URL) async -> Result {
        switch LinkKind(url: url) {
        case .youtube: if let meta = try? await youtube(url) { return Result(meta: meta, isFallback: false) }
        case .bilibili: if let meta = try? await bilibili(url) { return Result(meta: meta, isFallback: false) }
        case .x: if let meta = try? await twitter(url) { return Result(meta: meta, isFallback: false) }
        case .web: break
        }
        let page = try? await html(url)
        if let page, page.imageData != nil { return Result(meta: page, isFallback: false) }
        let preview = try? await generic(url)
        if var meta = page ?? preview {
            meta.imageData = meta.imageData ?? preview?.imageData
            return Result(meta: meta, isFallback: false)
        }
        return Result(meta: LinkMeta(url: url, site: siteName(url), title: ""), isFallback: true)
    }

    static func siteName(_ url: URL) -> String {
        switch LinkKind(url: url) {
        case .youtube: return "YouTube"
        case .bilibili: return "哔哩哔哩"
        case .x: return "X"
        case .web:
            let host = (url.host() ?? "").lowercased()
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
    }

    private static func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    private static func json(_ url: URL) async throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: try await fetch(url)) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return object
    }

    private static func imageData(_ string: String?) async -> Data? {
        guard let string else { return nil }
        for url in imageCandidates(string) {
            if let data = try? await fetch(url), let image = PlatformImage(data: data),
               image.size.width >= 48, image.size.height >= 48 { return data }
        }
        return nil
    }

    /// An image URL wrapped in a resizing proxy, like Xiaohongshu's
    /// `https://ci.xiaohongshu.com/http://sns-webpic….xhscdn.com/…?imageMogr2/crop/450x300`, is tried unwrapped
    /// first: the proxy often fails, and the original keeps its full size and aspect ratio.
    nonisolated static func imageCandidates(_ string: String) -> [URL] {
        var strings: [String] = []
        if string.count > 8, let inner = string.dropFirst(8).range(of: "https?://", options: .regularExpression) {
            let wrapped = String(string[inner.lowerBound...])
            strings += [String(wrapped.prefix { $0 != "?" }), wrapped]
        }
        strings.append(string)
        var seen = Set<URL>()
        return strings
            .map { $0.hasPrefix("http://") ? "https://" + $0.dropFirst(7) : $0 }
            .compactMap(URL.init(string:))
            .filter { seen.insert($0).inserted }
    }

    /// Downloads an icon and keeps it at most 192 px, preserving transparency.
    private static func iconData(_ string: String?) async -> Data? {
        guard let string, let url = URL(string: string),
              let data = try? await fetch(url), let image = PlatformImage(data: data),
              image.size.width >= 16 else { return nil }
        guard image.size.width > 192 else { return image.pngData() }
        return image.preparingThumbnail(of: CGSize(width: 192, height: 192 * image.size.height / image.size.width))?.pngData()
    }

    /// The site's touch icon or favicon at well-known paths.
    static func favicon(near url: URL) async -> Data? {
        let origin = "https://" + iconHost(url)
        if let data = await iconData(origin + "/apple-touch-icon.png") { return data }
        return await iconData(origin + "/favicon.ico")
    }

    /// Google's favicon service has 128 px icons for many sites that only ship a 16–32 px favicon.
    /// Short timeout because it's unreachable in mainland China.
    private static func googleFavicon(_ url: URL) async -> Data? {
        guard let api = URL(string: "https://www.google.com/s2/favicons?domain=\(iconHost(url))&sz=128") else { return nil }
        guard let (data, response) = try? await session.data(for: URLRequest(url: api, timeoutInterval: 3)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = PlatformImage(data: data), image.size.width >= 32 else { return nil }
        return data
    }

    private static func iconHost(_ url: URL) -> String {
        switch LinkKind(url: url) {
        case .youtube: "www.youtube.com"
        case .bilibili: "www.bilibili.com"
        case .x: "x.com"
        case .web: url.host() ?? ""
        }
    }

    private static func thumbnail(_ data: Data?, side: CGFloat) -> Data? {
        guard let data, let image = PlatformImage(data: data) else { return nil }
        return image.preparingThumbnail(of: CGSize(width: side, height: side))?.jpegData(compressionQuality: 0.85)
    }

    static func youtube(_ url: URL) async throws -> LinkMeta {
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [
            .init(name: "url", value: url.absoluteString),
            .init(name: "format", value: "json"),
        ]
        let j = try await json(components.url!)
        guard let title = j["title"] as? String, !title.isEmpty else { throw URLError(.cannotParseResponse) }
        let thumb = j["thumbnail_url"] as? String
        var data = await imageData(thumb?.replacingOccurrences(of: "hqdefault", with: "maxresdefault"))
        if data == nil { data = await imageData(thumb) }
        return LinkMeta(url: url, site: "YouTube", title: title,
                        authorName: j["author_name"] as? String, imageData: data)
    }

    static func twitter(_ url: URL) async throws -> LinkMeta {
        let api = URL(string: "https://api.fxtwitter.com" + url.path())!
        guard let tweet = try await json(api)["tweet"] as? [String: Any] else { throw URLError(.cannotParseResponse) }
        let author = tweet["author"] as? [String: Any] ?? [:]
        let media = tweet["media"] as? [String: Any]
        let photo = (media?["photos"] as? [[String: Any]])?.first?["url"] as? String
        let video = (media?["videos"] as? [[String: Any]])?.first?["thumbnail_url"] as? String
        let name = author["name"] as? String
        let handle = author["screen_name"] as? String
        let avatar = (author["avatar_url"] as? String)?.replacingOccurrences(of: "_normal.", with: "_400x400.")
        let text = tweet["text"] as? String ?? ""
        async let mediaData = imageData(photo ?? video)
        async let avatarImageData = imageData(avatar)
        return LinkMeta(url: url, site: "X",
                        title: text.isEmpty ? "Post by \(name ?? handle ?? "X")" : text,
                        authorName: name, authorHandle: handle,
                        imageData: await mediaData,
                        avatarData: thumbnail(await avatarImageData, side: 144))
    }

    static func bilibili(_ url: URL) async throws -> LinkMeta {
        var resolved = url
        if url.host() == "b23.tv" {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            resolved = try await session.data(for: request).1.url ?? url
        }
        let id = resolved.pathComponents.first { $0.hasPrefix("BV") || $0.lowercased().hasPrefix("av") }
        guard let id else { throw URLError(.unsupportedURL) }
        let query = id.hasPrefix("BV") ? "bvid=\(id)" : "aid=\(id.dropFirst(2))"
        let j = try await json(URL(string: "https://api.bilibili.com/x/web-interface/view?\(query)")!)
        guard j["code"] as? Int == 0, let data = j["data"] as? [String: Any],
              let title = data["title"] as? String, !title.isEmpty else { throw URLError(.cannotParseResponse) }
        let owner = data["owner"] as? [String: Any]
        let pic = (data["pic"] as? String)?.replacingOccurrences(of: "http://", with: "https://")
        let faceURL = owner?["face"] as? String
        async let cover = imageData(pic)
        async let face = imageData(faceURL)
        return LinkMeta(url: resolved, site: "哔哩哔哩", title: title,
                        authorName: owner?["name"] as? String,
                        imageData: await cover, avatarData: thumbnail(await face, side: 144))
    }

    private static let browserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private static let blockedTitles = ["安全验证", "验证码", "Sina Visitor System", "出错啦", "Just a moment", "Access Denied", "Attention Required"]
    private static let blockedHosts = ["sec.", "passport.", "captcha", "verify", "login."]

    /// Reads og:/twitter: tags directly so the image is the original rather than LinkPresentation's downscaled copy.
    static func html(_ url: URL) async throws -> LinkMeta {
        var request = URLRequest(url: url)
        request.setValue(browserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.mimeType?.contains("html") != false else { throw URLError(.badServerResponse) }
        let finalURL = http.url ?? url
        let finalHost = finalURL.host()?.lowercased() ?? ""
        guard !blockedHosts.contains(where: finalHost.contains) else { throw URLError(.userAuthenticationRequired) }

        let page = String(decoding: data.prefix(512 * 1024), as: UTF8.self)
        let tags = OpenGraph.tags(in: page)
        let title = (tags["og:title"] ?? tags["twitter:title"] ?? OpenGraph.title(in: page))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty, !blockedTitles.contains(where: title.contains) else {
            throw URLError(.cannotParseResponse)
        }
        let image = (tags["og:image:secure_url"] ?? tags["og:image"] ?? tags["twitter:image"] ?? tags["twitter:image:src"])
            .flatMap { URL(string: $0, relativeTo: finalURL)?.absoluteURL.absoluteString }
        let site = tags["og:site_name"].flatMap { $0.count <= 12 ? $0 : nil } ?? siteName(url)
        let icon = OpenGraph.icon(in: page).flatMap { URL(string: $0, relativeTo: finalURL)?.absoluteURL.absoluteString }
        async let imageResult = imageData(image)
        async let iconResult = iconData(icon)
        return LinkMeta(url: url, site: site, title: OpenGraph.removingSiteSuffix(site, from: title),
                        imageData: await imageResult, iconData: await iconResult)
    }

    static func generic(_ url: URL) async throws -> LinkMeta {
        let provider = LPMetadataProvider()
        provider.timeout = 8
        let metadata = try await provider.startFetchingMetadata(for: url)
        var data: Data?
        if let imageProvider = metadata.imageProvider {
            data = try? await withCheckedThrowingContinuation { continuation in
                _ = imageProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { @Sendable d, e in
                    if let e { continuation.resume(throwing: e) } else { continuation.resume(returning: d) }
                }
            }
        }
        let title = metadata.title.flatMap { title in blockedTitles.contains(where: title.contains) ? nil : title }
        guard title != nil || data != nil else { throw URLError(.cannotParseResponse) }
        return LinkMeta(url: url, site: siteName(url), title: title ?? siteName(url), imageData: data)
    }
}

enum OpenGraph {
    private static let metaTag = /<meta\b[^>]*>/.ignoresCase()
    private static let attribute = /([a-zA-Z:_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/
    private static let titleTag = /<title[^>]*>([^<]*)<\/title>/.ignoresCase()

    static func tags(in html: String) -> [String: String] {
        var result: [String: String] = [:]
        for match in html.matches(of: metaTag) {
            var attributes: [String: String] = [:]
            for pair in match.output.matches(of: attribute) {
                attributes[pair.output.1.lowercased()] = String(pair.output.2 ?? pair.output.3 ?? "")
            }
            guard let key = (attributes["property"] ?? attributes["name"])?.lowercased(),
                  let content = attributes["content"], !content.isEmpty, result[key] == nil else { continue }
            result[key] = decodeEntities(content)
        }
        return result
    }

    private static let linkTag = /<link\b[^>]*>/.ignoresCase()

    /// The best declared icon: apple-touch-icon first, then the largest `rel=icon`.
    static func icon(in html: String) -> String? {
        var best: (score: Int, href: String)?
        for match in html.matches(of: linkTag) {
            var attributes: [String: String] = [:]
            for pair in match.output.matches(of: attribute) {
                attributes[pair.output.1.lowercased()] = String(pair.output.2 ?? pair.output.3 ?? "")
            }
            guard let rel = attributes["rel"]?.lowercased(), let href = attributes["href"], !href.isEmpty,
                  !href.lowercased().hasSuffix(".svg") else { continue }
            let size = attributes["sizes"].flatMap { Int($0.lowercased().split(separator: "x").first ?? "") } ?? 0
            let score: Int
            if rel.contains("apple-touch-icon") {
                score = 10_000 + size
            } else if rel.split(separator: " ").contains("icon") {
                score = size
            } else {
                continue
            }
            if score > (best?.score ?? -1) { best = (score, decodeEntities(href)) }
        }
        return best?.href
    }

    /// "原来苹果 CEO 也是法拉利车迷？ - 小红书" → "原来苹果 CEO 也是法拉利车迷？", since the site is shown separately.
    static func removingSiteSuffix(_ site: String, from title: String) -> String {
        for separator in [" - ", " | ", " – ", " — ", "_"] where title.hasSuffix(separator + site) {
            let trimmed = title.dropLast(separator.count + site.count).trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? title : trimmed
        }
        return title
    }

    static func title(in html: String) -> String? {
        html.firstMatch(of: titleTag).map { decodeEntities(String($0.output.1)) }
    }

    private static let numericEntity = /&#(x?)([0-9a-fA-F]+);/

    private static func decodeEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        return string
            .replacing(numericEntity) { match in
                let radix = match.output.1.isEmpty ? 10 : 16
                return UInt32(match.output.2, radix: radix).flatMap(Unicode.Scalar.init).map { String($0) } ?? ""
            }
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
