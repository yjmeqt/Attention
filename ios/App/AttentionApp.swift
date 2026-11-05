import SwiftUI
import TipKit

@main
struct AttentionApp: App {
    @State private var library = Library(syncs: true)

    init() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "resetTips") { try? Tips.resetDatastore() }
        if UserDefaults.standard.string(forKey: "demoLinks") != nil || UserDefaults.standard.integer(forKey: "demoBulk") > 0 {
            Tips.hideAllTipsForTesting()
        }
        FrameMeter.shared.startIfRequested()
        #endif
        try? Tips.configure()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "shareProbe") {
                ShareProbeView()
            } else {
                HomeView(library: library)
            }
            #else
            HomeView(library: library)
            #endif
        }
    }
}
