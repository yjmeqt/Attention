#if DEBUG
import SwiftUI
import ScreenCaptureKit

/// Captures real app views using a separate, non-syncing demo library.
/// PNGs are written inside the sandbox's Documents/MacStoreShots folder.
@MainActor
enum MacStoreShots {
    static func run() async {
        let root = URL.documentsDirectory.appending(path: "MacStoreShots", directoryHint: .isDirectory)
        let library = Library(directory: root.appending(path: "Library"), syncs: false)
        let links = [
            "https://www.apple.com/macbook-pro/",
            "https://www.swift.org/",
            "https://en.wikipedia.org/wiki/Bauhaus",
            "https://www.nasa.gov/",
            "https://developer.apple.com/design/human-interface-guidelines/",
            "https://en.wikipedia.org/wiki/Kyoto",
            "https://www.apple.com/airpods-pro/",
            "https://en.wikipedia.org/wiki/Architecture",
        ]
        // Repair an interrupted first capture rather than treating a partial library as complete.
        for (index, link) in links.enumerated() {
            let url = URL(string: link)!
            let item = library.items.first(where: { $0.url == url }) ?? library.save(.link(url, image: nil))
            if item.title.isEmpty { await library.enrich(item) }
            library.addTag(index % 2 == 0 ? "Inspiration" : "Read later", to: [item])
            item.updatedAt = Date(timeIntervalSince1970: 1_790_000_000 - Double(index * 600))
        }
        library.save()
        let locale = UserDefaults.standard.string(forKey: "shotLocale") ?? "en-US"
        let folder = root.appending(path: locale, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for scene in ["library", "search", "detail"] {
                UserDefaults.standard.set(scene, forKey: "macShotScene")
                let controller = NSHostingController(rootView: LibraryView(library: library))
                controller.sceneBridgingOptions = [.toolbars, .title]
                let window = NSWindow(contentViewController: controller)
                window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
                window.toolbarStyle = .unified
                // Keep capture windows out of Stage Manager's scaled background strip.
                window.level = .floating
                window.collectionBehavior = [.canJoinAllApplications, .canJoinAllSpaces, .stationary]
                window.title = "Attention"
                window.setContentSize(CGSize(width: 1280, height: 760))
                window.isReleasedWhenClosed = false
                NSApp.setActivationPolicy(.regular)
                window.makeKeyAndOrderFront(nil)
                NSApp.activate()
                try await Task.sleep(for: .seconds(3))
                let content = try await SCShareableContent.currentProcess
                guard let source = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let configuration = SCStreamConfiguration()
                configuration.width = Int(window.frame.width * 2)
                configuration.height = Int(window.frame.height * 2)
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true
                configuration.ignoreGlobalClipSingleWindow = true
                configuration.scalesToFit = true
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(desktopIndependentWindow: source), configuration: configuration)
                let bitmap = NSBitmapImageRep(cgImage: image)
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try png.write(to: folder.appending(path: "mac-\(scene).png"))
                window.close()
            }
            try Data("complete".utf8).write(to: folder.appending(path: "complete"))
        } catch {
            try? Data(String(describing: error).utf8).write(to: root.appending(path: "error.txt"))
        }
        NSApp.terminate(nil)
    }
}
#endif
