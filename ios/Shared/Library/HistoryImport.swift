import Foundation

/// One-time import of the pre-library history (`History/index.json` plus a cover image per entry).
enum HistoryImport {
    private struct Entry: Decodable {
        var id: UUID
        var date: Date
        var meta: LinkMeta
    }

    static func run(into library: Library, from directory: URL = AppGroup.container.appending(path: "History")) {
        let index = directory.appending(path: "index.json")
        guard let data = try? Data(contentsOf: index) else { return }
        let entries = (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
        for entry in entries.reversed() {
            let key = DomainTag.key(for: entry.meta.url)
            guard library.item(forKey: key) == nil else { continue }
            var meta = entry.meta
            meta.imageData = try? Data(contentsOf: directory.appending(path: entry.id.uuidString))
            let item = library.upsert(key: key, url: entry.meta.url, site: meta.site, style: CardStyle())
            item.createdAt = entry.date
            item.updatedAt = entry.date
            library.setMeta(meta, for: item)
            item.updatedAt = entry.date
        }
        library.save()
        try? FileManager.default.moveItem(at: index, to: directory.appending(path: "index.imported.json"))
    }
}
