import SwiftUI
import UIKit

/// The system paste control drawn like a plain toolbar icon, so it shares Scan's glass.
/// SwiftUI's `PasteButton` always fills its background; this one pastes without the "Allow Paste" prompt too.
struct ToolbarPasteButton: View {
    let paste: ([NSItemProvider]) -> Void
    @Environment(\.colorScheme) private var colorScheme

    // The control's colors are fixed when it's made, so a new appearance needs a new control.
    var body: some View {
        PasteControl(paste: paste, isDark: colorScheme == .dark).id(colorScheme)
    }
}

private struct PasteControl: UIViewRepresentable {
    let paste: ([NSItemProvider]) -> Void
    let isDark: Bool

    func makeUIView(context: Context) -> UIPasteControl {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconOnly
        configuration.cornerStyle = .capsule
        // Close to the toolbar glass; a clear background turns the control off.
        configuration.baseBackgroundColor = isDark ? UIColor(white: 0.11, alpha: 1) : .white
        configuration.baseForegroundColor = isDark ? .white : .black
        let control = UIPasteControl(configuration: configuration)
        control.target = context.coordinator
        return control
    }

    func updateUIView(_ control: UIPasteControl, context: Context) {
        context.coordinator.onPaste = paste
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIPasteControl, context: Context) -> CGSize? {
        CGSize(width: 44, height: 44)
    }

    func makeCoordinator() -> Coordinator { Coordinator(paste: paste) }

    final class Coordinator: NSObject, UIPasteConfigurationSupporting {
        var onPaste: ([NSItemProvider]) -> Void
        var pasteConfiguration: UIPasteConfiguration? = UIPasteConfiguration(
            acceptableTypeIdentifiers: ItemProviders.pasteTypes.map(\.identifier))

        init(paste: @escaping ([NSItemProvider]) -> Void) { onPaste = paste }

        func canPaste(_ itemProviders: [NSItemProvider]) -> Bool { true }

        func paste(itemProviders: [NSItemProvider]) { onPaste(itemProviders) }
    }
}
