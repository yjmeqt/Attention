import AppKit
import UniformTypeIdentifiers

enum MacClipboard {
    private static var pasteboard: NSPasteboard { .general }

    /// Bumps whenever anything is copied, here or in another app.
    static var changeCount: Int { pasteboard.changeCount }

    /// A copied URL, or the first link in copied text, like "Check this out https://youtu.be/…".
    static func link() -> URL? {
        if let url = NSURL(from: pasteboard) as URL?, url.scheme?.hasPrefix("http") == true { return url }
        return pasteboard.string(forType: .string).flatMap(URL.extract(from:))
    }

    static func copy(_ url: URL) {
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        pasteboard.setString(url.absoluteString, forType: .string)
    }

    /// PNG for apps that take it, TIFF for the ones that only read AppKit's native image type.
    static func copy(_ image: NSImage) {
        guard let png = image.pngData() else { return }
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff = image.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
    }
}
