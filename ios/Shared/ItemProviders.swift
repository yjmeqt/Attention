import SwiftUI
import UniformTypeIdentifiers
import os

enum ItemProviders {
    static let linkTypes: [UTType] = [.url, .plainText, .text]
    static let pasteTypes: [UTType] = [.url, .plainText, .text, .image]
    nonisolated static let log = Logger(subsystem: "com.yjmeqt.attention", category: "share")

    /// Some hosts never call back for a type they advertise, so every load is bounded.
    private static let loadTimeout: Duration = .seconds(3)

    /// Load complete plain representations before looking for links within them.
    /// Payloads retain their order; only one representation is read from each provider.
    static func plainTexts(in providers: [NSItemProvider]) async -> [String] {
        var result: [String] = []
        for provider in providers {
            var value: String?
            if provider.canLoadObject(ofClass: String.self) {
                value = await load("plain text") { done in
                    _ = provider.loadObject(ofClass: String.self) { text, _ in done(text) }
                }
            }
            if value == nil {
                for type in provider.registeredTypeIdentifiers where UTType(type)?.conforms(to: .plainText) == true {
                    value = await load("plain text data") { done in
                        provider.loadItem(forTypeIdentifier: type) { item, _ in done(text(from: item)) }
                    }
                    if value != nil { break }
                }
            }
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(value) }
        }
        return result
    }

    static func explicitLink(in providers: [NSItemProvider]) async -> URL? {
        for provider in providers where provider.registeredTypeIdentifiers.contains(where: { UTType($0)?.conforms(to: .url) == true })
            && provider.canLoadObject(ofClass: URL.self) {
            if let url = await load("URL", { done in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in done(url) }
            }), isWebURL(url) { return url }
        }
        return nil
    }

    /// Some hosts register a URL under an opaque identifier rather than public.url.
    /// Only a complete standalone URL is safe to infer from such a representation.
    static func standaloneLink(in providers: [NSItemProvider]) async -> URL? {
        for provider in providers where !isImage(provider) {
            for type in provider.registeredTypeIdentifiers {
                if let known = UTType(type), known.conforms(to: .html) || known.conforms(to: .rtf) { continue }
                let value = await load("standalone URL representation") { done in
                    provider.loadItem(forTypeIdentifier: type) { item, _ in done(text(from: item)) }
                }
                if let value, let url = standaloneWebURL(in: value) { return url }
            }
        }
        return nil
    }

    static func standaloneWebURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        guard !trimmed.isEmpty, let match = detector?.firstMatch(in: trimmed, range: range),
              match.range == range, let url = match.url, isWebURL(url), url.host() != nil else { return nil }
        return url
    }

    private static func isWebURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    /// Returns the first web link in a share request: attachments first (as a URL, as text, then as
    /// whatever raw type they registered), then the item's attributed text and title.
    static func firstLink(in items: [NSExtensionItem], skippingImages: Bool = false) async -> URL? {
        log.info("share request: \(items.count, privacy: .public) item(s)")
        for (index, item) in items.enumerated() {
            let attachments = item.attachments ?? []
            log.info("item \(index, privacy: .public): \(attachments.count, privacy: .public) attachment(s), text: \(item.attributedContentText?.string ?? "nil", privacy: .public), title: \(item.attributedTitle?.string ?? "nil", privacy: .public)")
            if let url = await firstLink(in: attachments, skippingImages: skippingImages) { return url }
        }
        for item in items {
            for text in [item.attributedContentText?.string, item.attributedTitle?.string].compactMap(\.self) {
                if let url = webLink(in: text) {
                    log.info("found link in item text: \(url.absoluteString, privacy: .public)")
                    return url
                }
            }
        }
        log.info("no link found in share request")
        return nil
    }

    static func firstLink(in providers: [NSItemProvider], skippingImages: Bool = false) async -> URL? {
        for provider in providers where !(skippingImages && isImage(provider)) {
            if let url = await firstLink(in: provider) { return url }
        }
        return nil
    }

    /// The data of the first image attachment.
    static func firstImage(in providers: [NSItemProvider]) async -> Data? {
        for provider in providers where isImage(provider) {
            let type = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true } ?? UTType.image.identifier
            if let data = await load("image", timeout: .seconds(10), { done in _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in done(data) } }) {
                log.info("found image as \(type, privacy: .public): \(data.count, privacy: .public) bytes")
                return data
            }
            if provider.canLoadObject(ofClass: PlatformImage.self),
               let data = await load("image object", { done in
                   _ = provider.loadObject(ofClass: PlatformImage.self) { image, _ in done((image as? PlatformImage)?.pngData()) }
               }) {
                return data
            }
        }
        return nil
    }

    private static func isImage(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
    }

    private static func firstLink(in provider: NSItemProvider) async -> URL? {
        let types = provider.registeredTypeIdentifiers
        log.info("attachment types: \(types.joined(separator: ", "), privacy: .public)")
        if provider.canLoadObject(ofClass: URL.self),
           let url = await load("URL", { done in _ = provider.loadObject(ofClass: URL.self) { url, _ in done(url) } }),
           url.scheme?.hasPrefix("http") == true {
            log.info("found link as URL: \(url.absoluteString, privacy: .public)")
            return url
        }
        if provider.canLoadObject(ofClass: String.self),
           let text = await load("String", { done in _ = provider.loadObject(ofClass: String.self) { text, _ in done(text) } }),
           let url = webLink(in: text) {
            log.info("found link in text: \(url.absoluteString, privacy: .public)")
            return url
        }
        for type in types {
            let text = await load(type) { done in
                provider.loadItem(forTypeIdentifier: type) { item, error in
                    if let error { log.info("loadItem \(type, privacy: .public) failed: \(error.localizedDescription, privacy: .public)") }
                    done(text(from: item))
                }
            }
            if let text, let url = webLink(in: text) {
                log.info("found link in raw \(type, privacy: .public): \(url.absoluteString, privacy: .public)")
                return url
            }
        }
        return nil
    }

    static func webLink(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        return matches.compactMap(\.url).first { isWebURL($0) && $0.host() != nil }
    }

    private nonisolated static func text(from item: NSSecureCoding?) -> String? {
        switch item {
        case let url as URL: url.absoluteString
        case let string as String: string
        case let attributed as NSAttributedString: attributed.string
        case let data as Data: String(data: data, encoding: .utf8)
        default: nil
        }
    }

    /// Starts a callback-based load and returns its value, or nil after `loadTimeout`.
    private static func load<T: Sendable>(_ label: String, timeout: Duration = loadTimeout, _ start: (@escaping @Sendable (T?) -> Void) -> Void) async -> T? {
        let value: T? = await withCheckedContinuation { continuation in
            let once = Once(continuation)
            start { once.resume($0) }
            Task {
                try? await Task.sleep(for: timeout)
                once.resume(nil)
            }
        }
        if value == nil { log.info("load \(label, privacy: .public) gave nothing") }
        return value
    }
}

/// Resumes a continuation at most once, from whichever of the load or the timeout finishes first.
nonisolated private final class Once<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) { self.continuation = continuation }

    func resume(_ value: T?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
