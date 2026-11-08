import SwiftUI
import TipKit

@main
struct AttentionApp: App {
    @State private var library: Library

    init() {
        #if DEBUG
        let isSearchDemo = DemoLibrary.searchCorpus
        let library = isSearchDemo
            ? Library(directory: FileManager.default.temporaryDirectory.appending(path: "AttentionSearchDemo"), inMemory: true)
            : Library(syncs: true)
        if isSearchDemo { SearchDemoCorpus.seed(into: library) }
        _library = State(initialValue: library)
        if UserDefaults.standard.bool(forKey: "resetTips") { try? Tips.resetDatastore() }
        if isSearchDemo || UserDefaults.standard.string(forKey: "demoLinks") != nil || UserDefaults.standard.integer(forKey: "demoBulk") > 0 {
            Tips.hideAllTipsForTesting()
        }
        FrameMeter.shared.startIfRequested()
        #else
        _library = State(initialValue: Library(syncs: true))
        #endif
        try? Tips.configure()
    }

    var body: some Scene {
        WindowGroup {
            HomeView(library: library)
        }
    }
}
