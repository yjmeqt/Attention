import SwiftUI
import SafariServices
import LocalAuthentication

enum Opening {
    /// Whether this process can hand links to other apps; app extensions can't.
    static var canOpenApps: Bool {
        #if SHARE_EXTENSION
        false
        #else
        true
        #endif
    }

    /// Opens the link in the app that claims it (YouTube, Bilibili…), or calls `fallback`.
    static func openInApp(_ url: URL, fallback: @escaping () -> Void) {
        #if SHARE_EXTENSION
        fallback()
        #else
        UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { opened in
            if !opened { fallback() }
        }
        #endif
    }
}

struct BrowserLink: Identifiable {
    let url: URL
    var id: URL { url }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

enum DeviceOwner {
    enum Outcome { case authenticated, failed, unavailable }

    /// Face ID / Touch ID with the passcode as fallback.
    static func authenticate(reason: String) async -> Outcome {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            ItemProviders.log.error("authentication unavailable: \(error?.localizedDescription ?? "", privacy: .public)")
            return .unavailable
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) ? .authenticated : .failed
        } catch {
            return .failed
        }
    }
}
