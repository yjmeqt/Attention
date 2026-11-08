import StoreKit
import SwiftUI

struct SettingsView: View {
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
                        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = Self.version }
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
