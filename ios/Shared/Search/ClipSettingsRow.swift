#if os(iOS)
import SwiftUI

struct ClipSettingsRow: View {
    private var clip = ClipModel.shared

    var body: some View {
        switch clip.status {
        case .missing:
            Button {
                clip.download()
            } label: {
                Label("Download MobileCLIP", systemImage: "arrow.down.circle")
            }
        case let .downloading(fraction):
            VStack(alignment: .leading, spacing: 8) {
                Label("Downloading…", systemImage: "arrow.down.circle")
                ProgressView(value: fraction)
            }
        case .ready:
            LabeledContent {
                Button("Remove", role: .destructive) { clip.delete() }
                    .buttonStyle(.borderless)
            } label: {
                Label("MobileCLIP Ready", systemImage: "checkmark.circle")
            }
        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Button("Try Again") { clip.download() }
            }
        }
    }
}
#endif
