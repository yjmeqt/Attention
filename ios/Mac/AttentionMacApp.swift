import SwiftUI

/// A library window plus a menu bar item. The app is a menu bar app (`LSUIElement`) that shows in the Dock
/// only while the library window is open.
///
/// Windows and the status item are AppKit rather than SwiftUI scenes: built with the macOS 27 SDK and run
/// on macOS 26, re-evaluating a `MenuBarExtra` scene whenever its icon changed crashed in Swift's
/// main-actor check. An app body that never changes sidesteps that.
@main
struct AttentionMacApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let library = Library(syncs: true)
    private lazy var maker = CardMaker(library: library)
    private lazy var libraryWindow = LibraryWindow(library: library)
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var launchedAtLogin = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAtLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        statusItem = item

        let panel = NSHostingController(rootView: MenuPanel(maker: maker) { [weak self] in
            self?.popover.performClose(nil)
            self?.libraryWindow.show()
        })
        panel.sizingOptions = .preferredContentSize
        popover.contentViewController = panel
        popover.behavior = .transient
        followIcon()

        // Opened by hand, show the library; at login, stay in the menu bar.
        if !launchedAtLogin { libraryWindow.show() }
    }

    /// Opening the app again from the Finder or Launchpad brings the library back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        libraryWindow.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Keeps the status item's symbol in step with the maker; it isn't a SwiftUI view, so it's tracked by hand.
    private func followIcon() {
        withObservationTracking {
            statusItem?.button?.image = NSImage(systemSymbolName: maker.menuBarSymbol, accessibilityDescription: Brand.name)
        } onChange: { [weak self] in
            Task { @MainActor in self?.followIcon() }
        }
    }

    @objc private func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem?.button {
            maker.pickUpClipboard()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate()
        }
    }
}

/// The library window. Made fresh each time it opens, so Private is locked again after it closes.
final class LibraryWindow: NSObject, NSWindowDelegate {
    private let library: Library
    private var window: NSWindow?

    init(library: Library) { self.library = library }

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: LibraryView(library: library))
            controller.sceneBridgingOptions = [.toolbars, .title]
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.title = Brand.name
            window.setContentSize(CGSize(width: 1100, height: 720))
            window.minSize = CGSize(width: 640, height: 420)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("Library")
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        #if DEBUG
        // `-snapshotLibrary YES` puts a picture of the window on the clipboard a few seconds after it opens,
        // for checking the layout without screen-recording access.
        if UserDefaults.standard.bool(forKey: "snapshotLibrary") {
            Task {
                try? await Task.sleep(for: .seconds(6))
                guard let view = window?.contentView?.superview ?? window?.contentView,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let image = NSImage(size: view.bounds.size)
                image.addRepresentation(bitmap)
                MacClipboard.copy(image)
            }
        }
        #endif
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
