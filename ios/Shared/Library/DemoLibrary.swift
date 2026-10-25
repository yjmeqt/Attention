#if DEBUG
import Foundation

/// Fills an empty library for screenshots: `-demoLinks "https://a https://b"`, newest first.
enum DemoLibrary {
    static func run(into library: Library) async {
        guard library.items.isEmpty,
              let links = UserDefaults.standard.string(forKey: "demoLinks") else { return }
        let urls = links.split(separator: " ").compactMap { URL(string: String($0)) }
        for url in urls.reversed() {
            let item = library.save(.link(url, image: nil))
            _ = await library.enrich(item)
        }
    }
}
#endif
