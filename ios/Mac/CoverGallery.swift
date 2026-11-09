import SwiftUI

struct MacCoverPresentation: Identifiable {
    let id = UUID()
    let pages: [Page]
    let initial: Library.Cover

    struct Page: Identifiable {
        let id: Library.Cover
        let title: String
        let data: Data
    }
}

/// Browsing is local to this panel; only the confirmation button changes the card.
struct MacCoverGallery: View {
    let presentation: MacCoverPresentation
    @Binding var selectedCover: Library.Cover
    @State private var index: Int
    @State private var image: NSImage?
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @Environment(\.dismiss) private var dismiss

    init(presentation: MacCoverPresentation, selectedCover: Binding<Library.Cover>) {
        self.presentation = presentation
        _selectedCover = selectedCover
        _index = State(initialValue: presentation.pages.firstIndex { $0.id == presentation.initial } ?? 0)
    }

    private var page: MacCoverPresentation.Page { presentation.pages[index] }
    private var isSelected: Bool { selectedCover == page.id }
    private var scale: CGFloat { min(5, max(1, zoom * pinch)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(page.title).font(.headline)
                    Text("\(index + 1) / \(presentation.pages.count)")
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Previous", systemImage: "chevron.left") { move(-1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(index == 0)
                Button("Next", systemImage: "chevron.right") { move(1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(index == presentation.pages.count - 1)
                Divider().frame(height: 20)
                Button("Close", systemImage: "xmark") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .labelStyle(.iconOnly)
            .padding()

            GeometryReader { geometry in
                if let image, image.size.width > 0, image.size.height > 0 {
                    let fit = min(geometry.size.width / image.size.width, geometry.size.height / image.size.height)
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .frame(width: image.size.width * fit * scale, height: image.size.height * fit * scale)
                            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                            .accessibilityLabel(page.title)
                            .onTapGesture(count: 2) { zoom = zoom > 1 ? 1 : 2.5 }
                    }
                    .defaultScrollAnchor(.center)
                    .simultaneousGesture(MagnifyGesture()
                        .updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in zoom = min(5, max(1, zoom * value.magnification)) })
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(.fill.quinary)

            HStack(spacing: 12) {
                Button("Zoom Out", systemImage: "minus.magnifyingglass") { zoom = max(1, zoom / 1.5) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(zoom <= 1)
                Button("Zoom In", systemImage: "plus.magnifyingglass") { zoom = min(5, zoom * 1.5) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(zoom >= 5)
                Button("Fit") { zoom = 1 }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(zoom == 1)
                Spacer()
                Button(isSelected ? String(localized: "Currently Used") : String(localized: "Use as Cover")) {
                    selectedCover = page.id
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isSelected)
            }
            .padding()
        }
        .frame(minWidth: 520, idealWidth: 720, maxWidth: 1200, minHeight: 440, idealHeight: 600, maxHeight: 1000)
        .task(id: page.id) {
            image = nil
            zoom = 1
            image = ImageData.downsample(page.data, maxPixel: 4096).map(NSImage.init(cgImage:))
        }
    }

    private func move(_ offset: Int) {
        let next = index + offset
        guard presentation.pages.indices.contains(next) else { return }
        image = nil
        zoom = 1
        index = next
    }
}
