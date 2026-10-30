import AppKit
import Observation
import UniformTypeIdentifiers

/// The menu bar's half of the app: turns a link into a card image, from the panel's field or straight from
/// the clipboard with the hot key. Every link it handles is saved to the library, like a share on iOS.
@Observable
final class CardMaker {
    enum Phase: Equatable { case idle, working, ready, failed }

    let library: Library
    var input = ""
    private(set) var phase = Phase.idle
    private(set) var item: LibraryItem?
    private(set) var card: NSImage?
    /// Flashes a checkmark in the menu bar after the hot key copies a card.
    private(set) var copiedFlash = false

    /// The item's style once there is one; until then the style new items get.
    var style: CardStyle {
        get { item?.style ?? CardStyle.load() }
        set {
            newValue.save()
            if let item { library.setStyle(newValue, for: item) }
            render()
        }
    }

    var menuBarSymbol: String {
        if copiedFlash { return "checkmark.circle.fill" }
        return phase == .working ? "ellipsis.circle" : "link.circle"
    }

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var seenChangeCount = -1
    @ObservationIgnored private var hotkey: Hotkey?

    init(library: Library) {
        self.library = library
        hotkey = Hotkey { [weak self] in self?.copyCardFromClipboard() }
        #if DEBUG
        // `-pressHotkey YES` runs the hot key once at launch, for checking it without sending keystrokes.
        if UserDefaults.standard.bool(forKey: "pressHotkey") { copyCardFromClipboard() }
        #endif
    }

    /// When the panel opens: picks up a link copied since it was last open.
    func pickUpClipboard() {
        guard MacClipboard.changeCount != seenChangeCount else { return }
        seenChangeCount = MacClipboard.changeCount
        guard let url = MacClipboard.link(), DomainTag.key(for: url) != item?.key else { return }
        input = url.absoluteString
        make(url)
    }

    func makeFromInput() {
        guard let url = URL.extract(from: input) else {
            phase = .failed
            return
        }
        make(url)
    }

    /// The hot key: clipboard link in, card image out, without opening anything.
    func copyCardFromClipboard() {
        guard let url = MacClipboard.link() else {
            NSSound.beep()
            return
        }
        input = url.absoluteString
        make(url) { [weak self] in self?.copyImage(flash: true) }
    }

    private func make(_ url: URL, then completion: (() -> Void)? = nil) {
        task?.cancel()
        phase = .working
        let item = library.save(.link(url, image: nil))
        self.item = item
        task = Task {
            // Already saved with a preview, maybe on another device: no need to fetch it again.
            if item.title.isEmpty || item.coverData == nil { await library.enrich(item) }
            guard !Task.isCancelled else { return }
            render()
            completion?()
        }
    }

    private func render() {
        guard let item else { return }
        card = library.fullImage(item)
        phase = card == nil ? .failed : .ready
    }

    var shareURL: URL? { item.flatMap { library.meta(for: $0)?.shareURL ?? $0.url } }

    func copyImage(flash: Bool = false) {
        guard let card else { return }
        MacClipboard.copy(card)
        seenChangeCount = MacClipboard.changeCount
        guard flash else { return }
        copiedFlash = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copiedFlash = false
        }
    }

    func copyLink() {
        guard let shareURL else { return }
        MacClipboard.copy(shareURL)
        seenChangeCount = MacClipboard.changeCount
    }

    func cardFile() -> URL? {
        guard let card, let item else { return nil }
        return CardFile.write(card, for: item)
    }

    func save() {
        guard let card, let item else { return }
        CardFile.save(card, for: item)
    }
}

/// Card images as PNG files, for dragging into other apps and for Save.
enum CardFile {
    /// In the temporary folder, named after the item.
    static func write(_ image: NSImage, for item: LibraryItem) -> URL? {
        guard let png = image.pngData() else { return nil }
        let url = URL.temporaryDirectory.appending(path: name(for: item))
        return (try? png.write(to: url)) == nil ? nil : url
    }

    static func save(_ image: NSImage, for item: LibraryItem) {
        guard let png = image.pngData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = name(for: item)
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? png.write(to: url)
    }

    private static func name(for item: LibraryItem) -> String {
        let title = [item.title, item.site].first { !$0.isEmpty } ?? Brand.name
        let safe = title.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined()
        return String(safe.prefix(60)).trimmingCharacters(in: .whitespaces) + ".png"
    }
}
