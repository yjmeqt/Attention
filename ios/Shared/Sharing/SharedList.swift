import Foundation

/// A shared list's address: `https://attentioncard.com/l/<id>`, or the `open.` host the web page's
/// "View in Attention" button uses. Both are universal links (web/src/index.ts serves the AASA file).
struct SharedListLink: Identifiable, Hashable {
    let id: String

    static let hosts: Set<String> = ["attentioncard.com", "open.attentioncard.com"]
    static let apiBase = URL(string: "https://attentioncard.com/api/lists/")!

    init?(url: URL) {
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased(), Self.hosts.contains(host) else { return nil }
        let parts = url.path(percentEncoded: false).split(separator: "/")
        guard parts.count == 2, parts[0] == "l", parts[1].count == 10,
              parts[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        id = String(parts[1])
    }

    var webURL: URL { URL(string: "https://attentioncard.com/l/\(id)")! }
    var apiURL: URL { Self.apiBase.appending(path: id) }
}

/// A list as `GET /api/lists/<id>` returns it.
struct SharedList: Decodable, Equatable {
    struct Item: Decodable, Equatable, Identifiable {
        enum Kind: String, Decodable { case link, text }
        let kind: Kind
        let url: URL?
        let title: String?
        let site: String?
        let author: String?
        let thumb: URL?
        /// Width ÷ height of the thumbnail.
        let aspect: Double?
        let text: String?

        /// Stable within one list, which never changes after it's shared.
        var id: String { url?.absoluteString ?? text ?? "" }
    }

    let id: String
    let url: URL
    let title: String
    let createdAt: Date
    let items: [Item]

    var links: [Item] { items.filter { $0.kind == .link && $0.url != nil } }
}

enum SharedListError: Error, Equatable {
    /// The sharer revoked it, or Attention removed it after a report.
    case gone
    case notFound
    case unavailable
}

enum SharedListClient {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 date: \(string)"))
        }
        return decoder
    }()

    static func list(from data: Data, status: Int) throws(SharedListError) -> SharedList {
        switch status {
        case 200:
            guard let list = try? decoder.decode(SharedList.self, from: data) else { throw .unavailable }
            return list
        case 404: throw .notFound
        case 410: throw .gone
        default: throw .unavailable
        }
    }

    static func fetch(_ link: SharedListLink, session: URLSession = .shared) async throws(SharedListError) -> SharedList {
        // Always ask the server, so a list revoked a moment ago doesn't come back from the cache.
        var request = URLRequest(url: link.apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { throw .unavailable }
        return try list(from: data, status: http.statusCode)
    }
}

extension Library {
    /// Saves a shared list's links and texts, tagged with the list's title. Items already in the
    /// library keep their own data and just gain the tag. Previews are fetched afterwards.
    @discardableResult
    func save(_ list: SharedList) -> [LibraryItem] {
        let saved = list.items.compactMap { item -> LibraryItem? in
            switch item.kind {
            case .link: item.url.map { save(Capture(url: $0)) }
            case .text: item.text.map { save(Capture(text: $0)) }
            }
        }
        addTag(list.title, to: saved)
        return saved
    }
}
