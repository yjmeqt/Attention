import Foundation
import Observation

struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var meta: LinkMeta
}

@Observable
final class HistoryStore {
    private(set) var entries: [HistoryEntry] = []
    private let directory = AppGroup.container.appending(path: "History", directoryHint: .isDirectory)
    private var indexURL: URL { directory.appending(path: "index.json") }

    init() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        entries = (try? Data(contentsOf: indexURL))
            .flatMap { try? JSONDecoder().decode([HistoryEntry].self, from: $0) } ?? []
    }

    func add(_ meta: LinkMeta) {
        if let existing = entries.first(where: { $0.meta.url == meta.url }) { remove(existing) }
        var stored = meta
        stored.imageData = nil
        let entry = HistoryEntry(meta: stored)
        if let data = meta.imageData { try? data.write(to: imageURL(entry)) }
        entries.insert(entry, at: 0)
        while entries.count > 50 { remove(entries[entries.count - 1]) }
        save()
    }

    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        try? FileManager.default.removeItem(at: imageURL(entry))
        save()
    }

    func meta(for entry: HistoryEntry) -> LinkMeta {
        var meta = entry.meta
        meta.imageData = try? Data(contentsOf: imageURL(entry))
        return meta
    }

    private func imageURL(_ entry: HistoryEntry) -> URL {
        directory.appending(path: entry.id.uuidString)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}
