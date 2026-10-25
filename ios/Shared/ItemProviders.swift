import Foundation
import UniformTypeIdentifiers

enum ItemProviders {
    static let linkTypes: [UTType] = [.url, .plainText, .text]

    /// Returns the first web link found in the providers, whether shared as a URL or inside text.
    static func firstLink(in providers: [NSItemProvider]) async -> URL? {
        for provider in providers {
            if let url = await loadURL(from: provider), url.scheme?.hasPrefix("http") == true {
                return url
            }
            if let text = await loadText(from: provider), let url = URL.extract(from: text) {
                return url
            }
        }
        return nil
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        guard provider.canLoadObject(ofClass: URL.self) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { @Sendable url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        guard provider.canLoadObject(ofClass: String.self) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { @Sendable text, _ in
                continuation.resume(returning: text)
            }
        }
    }
}
