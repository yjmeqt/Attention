import SwiftUI

@main
struct AttentionApp: App {
    @State private var library = Library()

    var body: some Scene {
        WindowGroup {
            HomeView(library: library)
        }
    }
}
