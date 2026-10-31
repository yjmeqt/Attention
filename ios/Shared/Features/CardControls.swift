#if os(iOS)
import PhotosUI
#endif
import SwiftUI

struct SourceImageInfo: View {
    let meta: LinkMeta

    var body: some View {
        Group {
            if let size = meta.imagePixelSize {
                let small = size.width < 800
                let w = Int(size.width), h = Int(size.height)
                let title: LocalizedStringKey = small ? "Source image \(w) × \(h) · low resolution" : "Source image \(w) × \(h)"
                Label(title, systemImage: small ? "exclamationmark.triangle" : "photo")
                    .foregroundStyle(small ? .orange : .secondary)
            } else if meta.hasPreview {
                Label("No source image", systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TemplatePicker: View {
    let meta: LinkMeta
    @Binding var style: CardStyle

    private let scale: CGFloat = 0.2

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(CardTemplate.allCases.filter { $0 != .auto }) { template in
                    let selected = isSelected(template)
                    Button {
                        style.template = template
                    } label: {
                        VStack(spacing: 6) {
                            Text(template.label)
                                .font(.caption)
                                .foregroundStyle(selected ? .primary : .secondary)
                            thumbnail(template, selected: selected)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(template.label)
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    /// An item still on `.auto` shows the template it resolves to as selected.
    private func isSelected(_ template: CardTemplate) -> Bool {
        style.template.resolved(for: meta) == template
    }

    private func thumbnail(_ template: CardTemplate, selected: Bool) -> some View {
        var thumbStyle = style
        thumbStyle.template = template
        let size = CardView.size(for: meta, style: thumbStyle)
        return CardView(meta: meta, style: thumbStyle, height: size.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
            .clipShape(.rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 2 : 1)
            }
            .accessibilityHidden(true)
    }
}

/// A link's card image: its preview image, the image it was shared as, or one the user picks.
struct CoverPicker: View {
    let preview: PlatformImage?
    let shared: PlatformImage?
    let custom: PlatformImage?
    @Binding var cover: Library.Cover
    let pick: (Data) -> Void
    let removeCustom: () -> Void

    #if os(iOS)
    @State private var photo: PhotosPickerItem?
    #else
    @State private var importing = false
    #endif

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                option(String(localized: "Link Preview"), image: preview, for: .preview)
                if let shared {
                    option(String(localized: "Shared Image"), image: shared, for: .shared)
                }
                if let custom {
                    option(String(localized: "Your Image"), image: custom, for: .custom)
                        .contextMenu {
                            Button("Remove Image", systemImage: "trash", role: .destructive, action: removeCustom)
                        }
                }
                chooser
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        #if os(iOS)
        .task(id: photo) {
            guard let photo else { return }
            if let data = try? await photo.loadTransferable(type: Data.self) { pick(data) }
            self.photo = nil
        }
        #else
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result { pick(contentsOf: url) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.isFileURL else { return false }
            pick(contentsOf: url)
            return true
        }
        #endif
    }

    @ViewBuilder
    private var chooser: some View {
        let label = VStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 96, height: 72)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            Text("Choose Image")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        #if os(iOS)
        PhotosPicker(selection: $photo, matching: .images) { label }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Choose Image"))
        #else
        Button { importing = true } label: { label }
            .buttonStyle(.plain)
            .help("Choose an image, or drop one here")
            .accessibilityLabel(Text("Choose Image"))
        #endif
    }

    #if os(macOS)
    private func pick(contentsOf url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url) { pick(data) }
    }
    #endif

    private func option(_ title: String, image: PlatformImage?, for option: Library.Cover) -> some View {
        let selected = cover == option
        return Button { cover = option } label: {
            VStack(spacing: 6) {
                Color.clear
                    .frame(width: 96, height: 72)
                    .overlay {
                        if let image {
                            Image(platformImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary)
                        }
                    }
                    .background(.fill.tertiary)
                    .clipShape(.rect(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 2 : 1)
                    }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
