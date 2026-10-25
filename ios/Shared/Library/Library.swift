import Foundation
import Observation
import SwiftData
import UIKit

/// Every saved link and image, shared by the app and the share extension.
@Observable
final class Library {
    @ObservationIgnored var maxItems = 5000

    /// Newest first.
    private(set) var items: [LibraryItem] = []
    /// Bumped whenever an item's files change, so views showing thumbnails refresh.
    private(set) var revision = 0
    /// Items whose preview or text is still being fetched.
    var enriching: Set<UUID> = []

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored let directory: URL
    @ObservationIgnored private let thumbnails = NSCache<NSString, UIImage>()

    init(directory: URL = AppGroup.container.appending(path: "Library", directoryHint: .isDirectory),
         inMemory: Bool = false) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : ModelConfiguration(url: directory.appending(path: "Library.store"))
        let container: ModelContainer
        do {
            container = try ModelContainer(for: LibraryItem.self, configurations: configuration)
        } catch {
            fatalError("Couldn't open the library: \(error)")
        }
        context = ModelContext(container)
        context.autosaveEnabled = false
        reload()
    }

    func reload() {
        let descriptor = FetchDescriptor<LibraryItem>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        items = (try? context.fetch(descriptor)) ?? []
    }

    func item(forKey key: String) -> LibraryItem? {
        var descriptor = FetchDescriptor<LibraryItem>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Returns the existing item for `key`, moved to the top, or inserts a new one.
    @discardableResult
    func upsert(key: String, url: URL?, site: String, style: CardStyle) -> LibraryItem {
        if let existing = item(forKey: key) {
            existing.updatedAt = .now
            save()
            return existing
        }
        let item = LibraryItem(key: key, url: url, site: site, style: style)
        context.insert(item)
        save()
        enforceCap()
        return item
    }

    func save() {
        try? context.save()
        reload()
    }

    func delete(_ doomed: [LibraryItem]) {
        for item in doomed {
            try? FileManager.default.removeItem(at: folder(item))
            thumbnails.removeObject(forKey: item.id.uuidString as NSString)
            context.delete(item)
        }
        save()
    }

    func addTag(_ tag: String, to targets: [LibraryItem]) {
        let tag = Self.normalizedTag(tag)
        guard !tag.isEmpty else { return }
        for item in targets where !item.tags.contains(tag) { item.tags.append(tag) }
        save()
    }

    func removeTag(_ tag: String, from targets: [LibraryItem]) {
        for item in targets { item.tags.removeAll { $0 == tag } }
        save()
    }

    func setPrivate(_ isPrivate: Bool, _ targets: [LibraryItem]) {
        for item in targets {
            item.isPrivate = isPrivate
            protect(item)
        }
        save()
    }

    /// Manual tags across the library, most used first.
    var allTags: [String] {
        let counts = items.flatMap(\.tags).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    static func normalizedTag(_ tag: String) -> String {
        var tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        while tag.hasPrefix("#") { tag.removeFirst() }
        return tag
    }

    private func enforceCap() {
        let excess = items.count - maxItems
        guard excess > 0 else { return }
        delete(Array(items.reversed().filter { !$0.isPrivate }.prefix(excess)))
    }

    // MARK: - Files

    enum File: String { case cover, avatar, icon, source, thumbnail }

    func folder(_ item: LibraryItem) -> URL {
        directory.appending(path: item.id.uuidString, directoryHint: .isDirectory)
    }

    func data(_ file: File, of item: LibraryItem) -> Data? {
        try? Data(contentsOf: folder(item).appending(path: file.rawValue))
    }

    func write(_ data: Data?, _ file: File, of item: LibraryItem) {
        let url = folder(item).appending(path: file.rawValue)
        guard let data else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: folder(item), withIntermediateDirectories: true)
        try? data.write(to: url, options: item.isPrivate ? [.atomic, .completeFileProtection] : .atomic)
    }

    private func protect(_ item: LibraryItem) {
        let protection: FileProtectionType = item.isPrivate ? .complete : .completeUntilFirstUserAuthentication
        let files = (try? FileManager.default.contentsOfDirectory(at: folder(item), includingPropertiesForKeys: nil)) ?? []
        for file in files {
            try? FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: file.path)
        }
    }

    // MARK: - Metadata

    /// The link's metadata with its images, or nil for image items.
    func meta(for item: LibraryItem) -> LinkMeta? {
        guard let url = item.url else { return nil }
        return LinkMeta(url: url, site: item.site, title: item.title,
                        authorName: item.authorName, authorHandle: item.authorHandle,
                        imageData: data(.cover, of: item), avatarData: data(.avatar, of: item),
                        iconData: data(.icon, of: item))
    }

    func setMeta(_ meta: LinkMeta, for item: LibraryItem) {
        item.site = meta.site
        if meta.hasPreview || item.title.isEmpty { item.title = meta.title }
        item.authorName = meta.authorName
        item.authorHandle = meta.authorHandle
        write(meta.imageData, .cover, of: item)
        write(meta.avatarData, .avatar, of: item)
        write(meta.iconData, .icon, of: item)
        item.updatedAt = .now
        refreshThumbnail(item)
        save()
    }

    func setStyle(_ style: CardStyle, for item: LibraryItem) {
        guard item.style != style else { return }
        item.style = style
        refreshThumbnail(item)
        save()
    }

    // MARK: - Thumbnails

    func thumbnail(_ item: LibraryItem) -> UIImage? {
        let key = item.id.uuidString as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        if data(.thumbnail, of: item) == nil { refreshThumbnail(item) }
        guard let data = data(.thumbnail, of: item), let image = UIImage(data: data) else { return nil }
        thumbnails.setObject(image, forKey: key)
        return image
    }

    /// The full-size card for links, the shared image for images.
    func fullImage(_ item: LibraryItem) -> UIImage? {
        if let meta = meta(for: item) { return CardRenderer.render(meta, style: item.style) }
        return data(.source, of: item).flatMap(UIImage.init(data:))
    }

    func refreshThumbnail(_ item: LibraryItem) {
        let image: UIImage?
        if let meta = meta(for: item) {
            image = CardRenderer.render(meta, style: item.style, scale: 1.2)
        } else {
            image = data(.source, of: item).flatMap { ImageData.downsample($0, maxPixel: 720) }.map(UIImage.init(cgImage:))
        }
        guard let image, image.size.height > 0 else { return }
        item.thumbnailAspect = Double(image.size.width / image.size.height)
        write(image.jpegData(compressionQuality: 0.8), .thumbnail, of: item)
        thumbnails.removeObject(forKey: item.id.uuidString as NSString)
        revision += 1
    }
}
