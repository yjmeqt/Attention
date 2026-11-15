import Foundation

/// Which of the chosen items get shared, and why the others don't (docs/list-sharing.md, "上传什么").
/// Links and plain text go; images, private items and anything past the server's limit stay behind.
struct ListDraft {
    struct Skipped: Equatable {
        var privateItems = 0
        var images = 0
        var overLimit = 0
        var total: Int { privateItems + images + overLimit }
    }

    /// In feed order, newest first.
    let items: [LibraryItem]
    let skipped: Skipped

    /// A tag's live items.
    init(tag: String, library: Library) {
        self.init(items: library.items.filter { $0.tags.contains(tag) && !$0.isArchived })
    }

    /// Items the person picked, in the order given.
    init(items candidates: [LibraryItem]) {
        var skipped = Skipped()
        var shared: [LibraryItem] = []
        for item in candidates {
            if item.isPrivate {
                skipped.privateItems += 1
            } else if item.url == nil && !item.isTextOnly {
                skipped.images += 1
            } else if shared.count == ListUpload.limits.items {
                skipped.overLimit += 1
            } else {
                shared.append(item)
            }
        }
        self.items = shared
        self.skipped = skipped
    }
}

/// The body of `POST /api/lists`: the list's JSON plus a JPEG part per thumbnail (web/src/snapshot.ts).
struct ListUpload {
    /// The server's limits (web/src/snapshot.ts `limits`) and the app's own targets for thumbnails.
    nonisolated enum limits {
        static let items = 100
        static let thumbItems = 20
        static let title = 100
        static let linkTitle = 300
        static let site = 100
        static let author = 100
        static let text = 5000
        static let url = 2048
        static let thumbPixel = 480
        static let thumbBytes = 60 * 1024
    }

    var title: String
    var lang: String
    /// Each item as the snapshot's JSON object.
    var items: [[String: Any]]
    /// Part name → JPEG.
    var thumbs: [String: Data]
    /// Fixed when the upload is made, so `json` is the same bytes each time: the upload's assertion signs them.
    var createdAt = ISO8601DateFormatter().string(from: .now)

    var json: Data {
        let list: [String: Any] = [
            "v": 1,
            "title": title,
            "lang": lang,
            "createdAt": createdAt,
            "items": items,
        ]
        return (try? JSONSerialization.data(withJSONObject: list, options: [.sortedKeys])) ?? Data()
    }

    /// Builds the upload for `draft`. Thumbnails are compressed off the main actor.
    static func make(title: String, draft: ListDraft, library: Library,
                     lang: String = Locale.preferredLanguages.first ?? "en") async -> ListUpload {
        var items: [[String: Any]] = []
        var sources: [(part: String, data: Data)] = []
        for (index, item) in draft.items.enumerated() {
            if let url = item.url {
                var entry: [String: Any] = [
                    "kind": "link",
                    "url": clipped(url.cleanedForSharing.absoluteString, limits.url),
                    "title": clipped(item.title, limits.linkTitle),
                    "site": clipped(item.platformName, limits.site),
                ]
                if let author = item.authorName?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
                    entry["author"] = clipped(author, limits.author)
                }
                // Only the first 20 items keep a thumbnail; the server drops the rest.
                if index < limits.thumbItems, library.thumbnail(item) != nil, let data = library.data(.thumbnail, of: item) {
                    let part = "t\(index)"
                    entry["thumb"] = part
                    entry["aspect"] = (item.thumbnailAspect * 100).rounded() / 100
                    sources.append((part, data))
                }
                items.append(entry)
            } else if let text = item.text {
                items.append(["kind": "text", "text": clipped(text.trimmingCharacters(in: .whitespacesAndNewlines), limits.text)])
            }
        }
        let compressed = await Task.detached(priority: .userInitiated) {
            sources.compactMap { source in compressThumbnail(source.data).map { (source.part, $0) } }
        }.value
        let thumbs = Dictionary(compressed.map { ($0.0, $0.1.jpeg) }, uniquingKeysWith: { first, _ in first })
        let tints = Dictionary(compressed.compactMap { part, thumb in thumb.tint.map { (part, $0) } }, uniquingKeysWith: { first, _ in first })
        // A thumbnail that couldn't be made is left out rather than pointing at a missing part.
        for index in items.indices {
            guard let part = items[index]["thumb"] as? String else { continue }
            if thumbs[part] == nil {
                items[index]["thumb"] = nil
                items[index]["aspect"] = nil
            } else {
                // The web page colors the band under the photo with it, as the feed does.
                items[index]["tint"] = tints[part]
            }
        }
        return ListUpload(title: clipped(title.trimmingCharacters(in: .whitespacesAndNewlines), limits.title),
                          lang: lang, items: items, thumbs: thumbs)
    }

    /// At most 480 px on the long side and 60 KB, lowering the quality until it fits, with the color of its
    /// bottom edge as `#rrggbb`: the feed's band color (`CardTint`), which the web page can't work out itself.
    nonisolated static func compressThumbnail(_ data: Data) -> (jpeg: Data, tint: String?)? {
        guard let image = ImageData.downsample(data, maxPixel: limits.thumbPixel) else { return nil }
        let tint = ImageData.bottomEdgeColor(image).map { rgb in
            "#" + [rgb.red, rgb.green, rgb.blue].map { String(format: "%02x", Int(($0 * 255).rounded())) }.joined()
        }
        for quality in [0.8, 0.7, 0.6, 0.5, 0.4, 0.3] {
            if let jpeg = ImageData.jpeg(image, quality: quality), jpeg.count <= limits.thumbBytes { return (jpeg, tint) }
        }
        return nil
    }

    nonisolated static func clipped(_ string: String, _ limit: Int) -> String {
        string.count <= limit ? string : String(string.prefix(limit - 1)) + "…"
    }

    /// The multipart body, with `preview` as the link preview image when there is one.
    func multipart(preview: Data?, boundary: String) -> Data {
        var body = Data()
        func part(_ name: String, filename: String?, type: String, data: Data) {
            body.append(Data("--\(boundary)\r\n".utf8))
            let file = filename.map { "; filename=\"\($0)\"" } ?? ""
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\(file)\r\n".utf8))
            body.append(Data("Content-Type: \(type)\r\n\r\n".utf8))
            body.append(data)
            body.append(Data("\r\n".utf8))
        }
        part("list", filename: nil, type: "application/json", data: json)
        for (name, data) in thumbs.sorted(by: { $0.key < $1.key }) {
            part(name, filename: "\(name).jpg", type: "image/jpeg", data: data)
        }
        if let preview { part("preview", filename: "preview.jpg", type: "image/jpeg", data: preview) }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
}

enum ListSharingError: Error, Equatable {
    /// Too many uploads from this network in the last minute.
    case rateLimited
    /// Attention's daily upload limit for everyone is used up.
    case dailyLimit
    case uploadsPaused
    case rejected
    case unavailable
    /// The server doesn't know this device's App Attest key; attesting a new one fixes it.
    case unknownAttestKey
    /// The server requires App Attest and this upload didn't pass.
    case notVerified
}

/// Uploads a list and takes it down again (web/src/index.ts `createList`, `deleteList`).
enum ListSharingClient {
    static let endpoint = URL(string: "https://attentioncard.com/api/lists")!

    struct Created: Decodable, Equatable {
        let id: String
        let url: URL
        let deleteToken: String
    }

    static func created(from data: Data, status: Int) throws(ListSharingError) -> Created {
        switch status {
        case 201:
            guard let created = try? JSONDecoder().decode(Created.self, from: data),
                  SharedListLink(url: created.url) != nil else { throw .unavailable }
            return created
        case 429:
            let code = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw code == "daily_limit" ? .dailyLimit : .rateLimited
        case 401:
            let code = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw code == "unknown_attest_key" ? .unknownAttestKey : .notVerified
        case 503: throw .uploadsPaused
        case 400, 413: throw .rejected
        default: throw .unavailable
        }
    }

    /// Uploads with App Attest headers when the device can make them; once more with a new key if the server lost the old one.
    static func upload(_ upload: ListUpload, preview: Data?, session: URLSession = .shared) async throws(ListSharingError) -> Created {
        do {
            return try await send(upload, preview: preview, attest: await AppAttest.headers(for: upload.json, session: session), session: session)
        } catch .unknownAttestKey {
            AppAttest.forget()
            return try await send(upload, preview: preview, attest: await AppAttest.headers(for: upload.json, session: session), session: session)
        }
    }

    private static func send(_ upload: ListUpload, preview: Data?, attest: [String: String], session: URLSession) async throws(ListSharingError) -> Created {
        let boundary = "attention-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in attest { request.setValue(value, forHTTPHeaderField: name) }
        let body = upload.multipart(preview: preview, boundary: boundary)
        guard let (data, response) = try? await session.upload(for: request, from: body),
              let http = response as? HTTPURLResponse else { throw .unavailable }
        return try created(from: data, status: http.statusCode)
    }

    /// Takes the list down. A list that's already gone counts as taken down.
    static func revoke(id: String, token: String, session: URLSession = .shared) async throws(ListSharingError) {
        var request = URLRequest(url: SharedListLink.apiBase.appending(path: id), timeoutInterval: 20)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { throw .unavailable }
        switch http.statusCode {
        case 200..<300, 404, 410: return
        case 401, 403: throw .rejected
        default: throw .unavailable
        }
    }
}
