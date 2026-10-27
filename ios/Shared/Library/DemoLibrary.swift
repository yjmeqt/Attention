#if DEBUG
import Foundation

/// Fills an empty library for screenshots: `-demoLinks "https://a https://b"`, newest first.
/// `-demoTags "0=Music,Watch;2=Travel"` tags items by their position in `demoLinks`,
/// `-demoPrivate "10 11"` moves those to Private.
enum DemoLibrary {
    static func run(into library: Library) async {
        guard library.items.isEmpty,
              let links = UserDefaults.standard.string(forKey: "demoLinks") else { return }
        let urls = links.split(separator: " ").compactMap { URL(string: String($0)) }
        let saved: [LibraryItem] = Array(urls.reversed().map { library.save(.link($0, image: nil)) }.reversed())
        // All at once, so the library is ready before the screenshot is taken.
        let enriching = saved.map { item in Task { _ = await library.enrich(item) } }
        for task in enriching { await task.value }
        // With thirty at once a few time out; retry those here, so the app's own retry later
        // doesn't bump them to the top and shuffle the order the screenshots rely on.
        for _ in 0..<2 {
            for item in saved where item.title.isEmpty && library.data(.cover, of: item) == nil { _ = await library.enrich(item) }
        }
        library.retriedPreviews.formUnion(saved.map(\.id))
        // Enriching bumps each item to the top; restore the demoLinks order, a few minutes apart.
        for (index, item) in saved.enumerated() { item.updatedAt = .now.addingTimeInterval(Double(index) * -420) }
        library.save()
        for entry in (UserDefaults.standard.string(forKey: "demoTags") ?? "").split(separator: ";") {
            let parts = entry.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let index = Int(parts[0]), saved.indices.contains(index) else { continue }
            for tag in parts[1].split(separator: ",") { library.addTag(String(tag), to: [saved[index]]) }
        }
        let hidden = (UserDefaults.standard.string(forKey: "demoPrivate") ?? "").split(separator: " ")
            .compactMap { Int($0) }.filter(saved.indices.contains).map { saved[$0] }
        if !hidden.isEmpty { library.setPrivate(true, hidden) }
        // Tells the screenshot script the library is in place.
        try? Data().write(to: URL.documentsDirectory.appending(path: "demo-ready"))
    }

    /// `-demoOpen 0` opens that item, `-demoSearch text` fills the search field, `-demoTagFilter Music` turns a tag on.
    static var open: Int? { UserDefaults.standard.object(forKey: "demoOpen") != nil ? UserDefaults.standard.integer(forKey: "demoOpen") : nil }
    static var search: String? { UserDefaults.standard.string(forKey: "demoSearch") }
    static var tagFilter: String? { UserDefaults.standard.string(forKey: "demoTagFilter") }
    /// `-demoUnlockPrivate YES` opens Private, still locked, and asks for Face ID.
    static var unlocksPrivate: Bool { UserDefaults.standard.bool(forKey: "demoUnlockPrivate") }
}
#endif
