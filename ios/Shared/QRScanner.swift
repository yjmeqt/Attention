import SwiftUI
import PhotosUI
import VisionKit
import CoreImage

struct QRScanSheet: View {
    let onLink: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var message: String?

    private var cameraAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if cameraAvailable {
                    QRCameraView { payload in handle(payload) }
                        .ignoresSafeArea()
                    ScanFrame()
                } else {
                    ContentUnavailableView("Camera unavailable", systemImage: "camera",
                                           description: Text("Choose a photo with a QR code instead."))
                }
                VStack(spacing: 12) {
                    if let message {
                        Text(message)
                            .font(.footnote)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: .capsule)
                    }
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .task(id: photo) {
                guard let photo else { return }
                guard let data = try? await photo.loadTransferable(type: Data.self),
                      let payload = QRDecoder.firstPayload(in: data) else {
                    message = "No QR code found in that photo."
                    return
                }
                handle(payload)
            }
        }
    }

    private func handle(_ payload: String) {
        guard let url = URL.extract(from: payload) else {
            message = "That QR code doesn't contain a link."
            return
        }
        onLink(url)
        dismiss()
    }
}

private struct ScanFrame: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(.white.opacity(0.9), lineWidth: 3)
            .frame(width: 240, height: 240)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }
}

private struct QRCameraView: UIViewControllerRepresentable {
    let onPayload: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onPayload = onPayload
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPayload: onPayload) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onPayload: (String) -> Void
        private var delivered = false

        init(onPayload: @escaping (String) -> Void) { self.onPayload = onPayload }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            deliver(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            deliver([item])
        }

        private func deliver(_ items: [RecognizedItem]) {
            guard !delivered else { return }
            for case .barcode(let barcode) in items {
                guard let payload = barcode.payloadStringValue else { continue }
                if URL.extract(from: payload) != nil { delivered = true }
                onPayload(payload)
                return
            }
        }
    }
}

enum QRDecoder {
    static func firstPayload(in data: Data) -> String? {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]),
              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { return nil }
        return detector.features(in: image)
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            .first
    }
}
