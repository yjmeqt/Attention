import SwiftUI
import TipKit

@main
struct AttentionApp: App {
    @State private var library = Library()

    init() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "resetTips") { try? Tips.resetDatastore() }
        if UserDefaults.standard.string(forKey: "demoLinks") != nil { Tips.hideAllTipsForTesting() }
        #endif
        try? Tips.configure()
    }

    var body: some Scene {
        WindowGroup {
            HomeView(library: library)
        }
    }
}
