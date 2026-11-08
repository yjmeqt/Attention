import StoreKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(TextCardPromotion.key, store: AppGroup.defaults) private var showsAppStoreQR = true
    @AppStorage(ShareDefault.key, store: AppGroup.defaults) private var shareDefault = ShareDefault.link
    @Environment(\.requestReview) private var requestReview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Default Share Format", selection: $shareDefault) {
                        Label { Text("Link or Text") } icon: { Image(systemName: "link").foregroundStyle(.primary) }
                            .tag(ShareDefault.link)
                        Label { Text("Image") } icon: { Image(systemName: "photo").foregroundStyle(.primary) }
                            .tag(ShareDefault.image)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Default Share Format")
                } footer: {
                    Text("Share links as links and text as text, or share any item as an image. Touch and hold Share for the other options.")
                }
                Section {
                    Toggle("Show App Store QR on Text Images", isOn: $showsAppStoreQR)
                } footer: {
                    Text("Add a QR code linking to Attention in the App Store when sharing text as an image.")
                }
                #if os(iOS) && !SHARE_EXTENSION
                Section {
                    ClipSettingsRow()
                } header: {
                    Text("Smart Image Search")
                } footer: {
                    Text("Downloads Apple's MobileCLIP (~100 MB) from GitHub so you can search by what's in a picture. Kept only on this device. Needs a network that can reach GitHub; if Apple Intelligence isn't available, Chinese queries use the Translate languages already on this device.")
                }
                #endif
                Section {
                    Button {
                        requestReview()
                    } label: {
                        Label("Rate \(Brand.name)", systemImage: "star")
                    }
                    Link(destination: Brand.privacyPolicyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    LabeledContent {
                        Text(Self.version)
                    } label: {
                        Label("Version", systemImage: "info.circle")
                    }
                    .contextMenu {
                        Button("Copy", systemImage: "doc.on.doc") { Clipboard.copy(Self.version) }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
