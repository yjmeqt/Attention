import SwiftUI

@main
struct OpticShareApp: App {
    @State private var library = Library()

    var body: some Scene {
        WindowGroup {
            HomeView(library: library)
        }
    }
}
