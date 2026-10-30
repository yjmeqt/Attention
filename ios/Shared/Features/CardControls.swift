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
                ForEach(CardTemplate.allCases) { template in
                    Button {
                        style.template = template
                    } label: {
                        VStack(spacing: 6) {
                            thumbnail(template)
                            Text(template == .auto ? String(localized: "Auto · \(template.resolved(for: meta).label)") : template.label)
                                .font(.caption)
                                .foregroundStyle(style.template == template ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(template.label)
                    .accessibilityAddTraits(style.template == template ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func thumbnail(_ template: CardTemplate) -> some View {
        var thumbStyle = style
        thumbStyle.template = template
        let size = CardView.size(for: meta, style: thumbStyle)
        let selected = style.template == template
        return CardView(meta: meta, style: thumbStyle)
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

/// For links shared as an image: the link's preview image or the shared image.
struct CoverPicker: View {
    let preview: PlatformImage?
    let shared: PlatformImage?
    @Binding var usesShared: Bool

    var body: some View {
        HStack(spacing: 12) {
            option(String(localized: "Link Preview"), image: preview, selected: !usesShared) { usesShared = false }
            option(String(localized: "Shared Image"), image: shared, selected: usesShared) { usesShared = true }
        }
    }

    private func option(_ title: String, image: PlatformImage?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Color.clear
                    .frame(width: 96, height: 72)
                    .overlay {
                        if let image { Image(platformImage: image).resizable().scaledToFill() }
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
