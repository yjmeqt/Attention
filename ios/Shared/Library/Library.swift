import SwiftUI
import Observation
import SwiftData
import CoreData

/// Every saved link and image, shared by the app and the share extension, and synced through iCloud.
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
    @ObservationIgnored private let thumbnails = NSCache<NSString, PlatformImage>()
    @ObservationIgnored private let tints = NSCache<NSString, Tint>()
    /// Items whose tile was regenerated this session, so ones without a photo aren't retried every render.
    @ObservationIgnored private var checked: Set<UUID> = []
    @ObservationIgnored var retriedPreviews: Set<UUID> = []
    @ObservationIgnored private var remoteChanges: (any NSObjectProtocol)?
    @ObservationIgnored private var pendingReload: Task<Void, Never>?

    /// `syncs` is for the apps. The share extension writes to the same store without syncing it;
    /// the app uploads those changes from the store's history the next time it runs.
    init(directory: URL = AppGroup.container.appending(path: "Library", directoryHint: .isDirectory),
         inMemory: Bool = false, syncs: Bool = false) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cloud: ModelConfiguration.CloudKitDatabase = syncs ? CloudSync.containerID.map { .private($0) } ?? .none : .none
        let configuration = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            : ModelConfiguration(url: directory.appending(path: "Library.store"), cloudKitDatabase: cloud)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: LibraryItem.self, configurations: configuration)
        } catch {
            fatalError("Couldn't open the library: \(error)")
        }
        context = ModelContext(container)
        context.autosaveEnabled = false
        reload()
        if syncs { observeRemoteChanges() }
    }

    /// Imports from iCloud (and saves by the share extension) arrive as remote changes to the store.
    /// They come in bursts, so a reload waits for a quiet moment.
    private func observeRemoteChanges() {
        remoteChanges = NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingReload?.cancel()
                self.pendingReload = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    self.reload()
                    self.mergeDuplicates()
                    self.revision += 1
                }
            }
        }
    }

    /// Two devices can save the same link before they sync. Every device keeps the same copy, the one
    /// with the lowest id, so they agree without talking, and folds the others into it.
    func mergeDuplicates() {
        let groups = Dictionary(grouping: items, by: \.key).values.filter { $0.count > 1 }
        guard !groups.isEmpty else { return }
        for group in groups {
            let sorted = group.sorted { $0.id.uuidString < $1.id.uuidString }
            let keeper = sorted[0]
            for other in sorted.dropFirst() {
                keeper.createdAt = min(keeper.createdAt, other.createdAt)
                keeper.updatedAt = max(keeper.updatedAt, other.updatedAt)
                keeper.tags += other.tags.filter { !keeper.tags.contains($0) }
                keeper.isPrivate = keeper.isPrivate || other.isPrivate
                if keeper.title.isEmpty { keeper.title = other.title }
                if keeper.ocrText == nil { keeper.ocrText = other.ocrText }
                if keeper.coverData == nil { keeper.coverData = other.coverData }
                if keeper.avatarData == nil { keeper.avatarData = other.avatarData }
                if keeper.iconData == nil { keeper.iconData = other.iconData }
                if keeper.sourceData == nil { keeper.sourceData = other.sourceData }
                try? FileManager.default.removeItem(at: folder(other))
                context.delete(other)
            }
            refreshThumbnail(keeper)
        }
        save()
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

    func setArchived(_ isArchived: Bool, _ targets: [LibraryItem]) {
        for item in targets { item.isArchived = isArchived }
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

    /// Over the cap, the oldest archived items go first, then the oldest others. Private items are never removed.
    private func enforceCap() {
        let excess = items.count - maxItems
        guard excess > 0 else { return }
        let oldest = items.reversed().filter { !$0.isPrivate }
        delete(Array((oldest.filter(\.isArchived) + oldest.filter { !$0.isArchived }).prefix(excess)))
    }

    // MARK: - Files

    /// The thumbnail is a local cache each device makes from the synced images; the rest sync with the item.
    enum File: String { case cover, avatar, icon, source, thumbnail = "tile" }

    /// Holds the item's local cache.
    func folder(_ item: LibraryItem) -> URL {
        directory.appending(path: item.id.uuidString, directoryHint: .isDirectory)
    }

    func data(_ file: File, of item: LibraryItem) -> Data? {
        switch file {
        case .cover: item.coverData
        case .avatar: item.avatarData
        case .icon: item.iconData
        case .source: item.sourceData
        case .thumbnail: try? Data(contentsOf: folder(item).appending(path: file.rawValue))
        }
    }

    func write(_ data: Data?, _ file: File, of item: LibraryItem) {
        switch file {
        case .cover: item.coverData = data
        case .avatar: item.avatarData = data
        case .icon: item.iconData = data
        case .source: item.sourceData = data
        case .thumbnail:
            let url = folder(item).appending(path: file.rawValue)
            guard let data else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            try? FileManager.default.createDirectory(at: folder(item), withIntermediateDirectories: true)
            #if os(iOS)
            try? data.write(to: url, options: item.isPrivate ? [.atomic, .completeFileProtection] : .atomic)
            #else
            try? data.write(to: url, options: .atomic)
            #endif
        }
    }

    private func protect(_ item: LibraryItem) {
        #if os(iOS)
        let protection: FileProtectionType = item.isPrivate ? .complete : .completeUntilFirstUserAuthentication
        let files = (try? FileManager.default.contentsOfDirectory(at: folder(item), includingPropertiesForKeys: nil)) ?? []
        for file in files {
            try? FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: file.path)
        }
        #endif
    }

    // MARK: - Metadata

    /// The link's metadata with its images, or nil for image items.
    func meta(for item: LibraryItem) -> LinkMeta? {
        guard let url = item.url else { return nil }
        return LinkMeta(url: url, site: item.site, title: item.title,
                        authorName: item.authorName, authorHandle: item.authorHandle,
                        imageData: coverData(item), avatarData: data(.avatar, of: item),
                        iconData: data(.icon, of: item))
    }

    /// The image a link's card and tile show: its preview image, or the image it was shared as.
    func coverData(_ item: LibraryItem) -> Data? {
        if item.usesSharedImage, let source = data(.source, of: item) { return source }
        return data(.cover, of: item)
    }

    /// Both a preview image and a different shared image, so there's a choice to make.
    func hasCoverChoice(_ item: LibraryItem) -> Bool {
        guard !item.isImage, let source = data(.source, of: item), let cover = data(.cover, of: item) else { return false }
        return source != cover
    }

    func setUsesSharedImage(_ uses: Bool, for item: LibraryItem) {
        guard item.usesSharedImage != uses else { return }
        item.usesSharedImage = uses
        refreshThumbnail(item)
        save()
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
        save()
    }

    // MARK: - Thumbnails

    /// The feed image: the link's preview image or the shared image. Nil when there's none.
    func thumbnail(_ item: LibraryItem) -> PlatformImage? {
        let key = item.id.uuidString as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        if data(.thumbnail, of: item) == nil, checked.insert(item.id).inserted { refreshThumbnail(item) }
        guard let data = data(.thumbnail, of: item), let image = PlatformImage(data: data) else { return nil }
        thumbnails.setObject(image, forKey: key)
        return image
    }

    /// The band color under a tile's photo, taken from the photo's bottom edge.
    func tint(_ item: LibraryItem) -> Tint? {
        let key = item.id.uuidString as NSString
        if let cached = tints.object(forKey: key) { return cached }
        guard let image = thumbnail(item)?.cgImage, let rgb = ImageData.bottomEdgeColor(image) else { return nil }
        let tint = Tint(color: Color(red: rgb.red, green: rgb.green, blue: rgb.blue),
                        isDark: 0.299 * rgb.red + 0.587 * rgb.green + 0.114 * rgb.blue < 0.6)
        tints.setObject(tint, forKey: key)
        return tint
    }

    final class Tint {
        let color: Color
        let isDark: Bool
        init(color: Color, isDark: Bool) { self.color = color; self.isDark = isDark }
    }

    func favicon(_ item: LibraryItem) -> PlatformImage? {
        let key = "icon-\(item.id.uuidString)" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let data = data(.icon, of: item), let cgImage = ImageData.downsample(data, maxPixel: 128) else { return nil }
        let image = PlatformImage(cgImage: cgImage)
        thumbnails.setObject(image, forKey: key)
        return image
    }

    /// The full-size card for links, the shared image for images.
    func fullImage(_ item: LibraryItem) -> PlatformImage? {
        if let meta = meta(for: item) { return CardRenderer.render(meta, style: item.style) }
        return data(.source, of: item).flatMap(PlatformImage.init(data:))
    }

    /// Tiles crop their photo to this range, like Messages link previews.
    static let tileAspects = 0.6...1.9

    func refreshThumbnail(_ item: LibraryItem) {
        let source = item.isImage ? data(.source, of: item) : coverData(item)
        let image = source.flatMap { ImageData.downsample($0, maxPixel: 720) }
            .flatMap { item.isImage || min($0.width, $0.height) >= 200 ? $0 : nil }
        let aspect = image.map { min(max(Double($0.width) / Double($0.height), Self.tileAspects.lowerBound), Self.tileAspects.upperBound) } ?? 0
        write(image.flatMap { ImageData.jpeg($0, quality: 0.8) }, .thumbnail, of: item)
        try? FileManager.default.removeItem(at: folder(item).appending(path: "thumbnail"))
        thumbnails.removeObject(forKey: item.id.uuidString as NSString)
        thumbnails.removeObject(forKey: "icon-\(item.id.uuidString)" as NSString)
        tints.removeObject(forKey: item.id.uuidString as NSString)
        item.thumbnailAspect = aspect
        revision += 1
    }
}
