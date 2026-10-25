import SwiftUI

@main
struct OpticShareApp: App {
    var body: some Scene {
        WindowGroup {
            CardMakerView(watchesClipboard: true, allowsScanning: true)
        }
    }
}
