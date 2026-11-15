import SwiftUI

/// A staggered grid: each item goes to the currently shortest column. Columns are lazy, so
/// thousands of items scroll smoothly; heights come from each item's stored aspect ratio.
struct Waterfall<Content: View>: View {
    let items: [LibraryItem]
    let columns: Int
    var spacing: CGFloat = 12
    @ViewBuilder let content: (LibraryItem) -> Content

    var body: some View {
        let lanes = Self.lanes(for: items, columns: columns)
        HStack(alignment: .top, spacing: spacing) {
            ForEach(lanes.indices, id: \.self) { index in
                LazyVStack(spacing: spacing) {
                    ForEach(lanes[index], id: \.id) { content($0) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    static func lanes(for items: [LibraryItem], columns: Int) -> [[LibraryItem]] {
        let count = max(columns, 1)
        var lanes = Array(repeating: [LibraryItem](), count: count)
        var heights = Array(repeating: 0.0, count: count)
        for item in items {
            let lane = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            lanes[lane].append(item)
            heights[lane] += (item.thumbnailAspect > 0 ? 1 / item.thumbnailAspect : 0.25) + 0.35
        }
        return lanes
    }

    static func columns(for width: CGFloat) -> Int {
        min(6, max(2, Int(width / 240)))
    }
}

struct FeedTile: View {
    let item: LibraryItem
    let library: Library
    var isSelecting = false
    var isSelected = false
    var onOpen: (() -> Void)?

    var body: some View {
        // Hosted cells and context-menu previews can outlive a deleted SwiftData model.
        if item.modelContext != nil && !item.isDeleted {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        let _ = library.revision
        let photo = library.thumbnail(item)
        // An image without a title shows just its eyebrow under the photo.
        FeedTileFace(photo: photo, aspect: item.thumbnailAspect, tint: library.tint(item).map { CardTint(color: $0.color, isDark: $0.isDark) },
                     title: photo != nil && item.isImage && item.title.isEmpty ? nil : item.displayTitle) {
            Eyebrow(item: item, library: library)
        } footer: {
            footerRow
        }
        .overlay(alignment: .topTrailing) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.black.opacity(0.3)))
                    .padding(8)
            }
        }
        .overlay {
            if library.enriching.contains(item.id) {
                ProgressView().padding(10).background(.regularMaterial, in: .circle)
            }
        }
        .opacity(isSelecting && !isSelected ? 0.85 : 1)
        .contentShape(.rect(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Time on the left; links get an Open button on the right, like the App Store's Get button.
    private var footerRow: some View {
        HStack {
            footer
            Spacer(minLength: 4)
            if let onOpen, item.url != nil {
                Button("Open", action: onOpen)
                    .font(.caption.weight(.bold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if item.isPrivate { Image(systemName: "lock.fill") }
            Text(min(item.updatedAt, .now).formatted(.relative(presentation: .named, unitsStyle: .narrow)))
                .lineLimit(1)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

/// How every feed tile looks: the app's feed, a list someone shared, and that list's link preview.
/// A photo over a band in the photo's own color, like App Store Today cards; without a photo, the
/// same text on a plain band.
struct FeedTileFace<Eyebrow: View, Footer: View>: View {
    let photo: PlatformImage?
    /// Width ÷ height of the photo's box.
    let aspect: Double
    /// The band's color, from the photo's bottom edge.
    let tint: CardTint?
    /// Under a photo, nil leaves the band to the eyebrow and footer.
    let title: String?
    var titleLines = 3
    var lockupLines = 6
    /// In the feed, cells have a set height and the photo takes what the band leaves; elsewhere the photo
    /// keeps its aspect ratio and the tile is as tall as it needs.
    var fillsCell = true
    @ViewBuilder let eyebrow: () -> Eyebrow
    @ViewBuilder let footer: () -> Footer

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let photo {
                card(photo)
            } else {
                lockup
            }
        }
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator.opacity(0.4), lineWidth: 0.5)
        }
    }

    private func card(_ photo: PlatformImage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Full width in a cell of a set height: the photo takes whatever the band leaves.
            Color.clear
                .aspectRatio(aspect, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: fillsCell ? .infinity : nil)
                .overlay { Image(platformImage: photo).resizable().scaledToFill() }
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                eyebrow()
                if let title {
                    Text(verbatim: title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(titleLines)
                        .multilineTextAlignment(.leading)
                }
                footer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .background(tint.map(\.color) ?? .secondaryBackground)
            .environment(\.colorScheme, tint.map { $0.isDark ? .dark : .light } ?? colorScheme)
        }
    }

    private var lockup: some View {
        VStack(alignment: .leading, spacing: 4) {
            eyebrow()
            Text(verbatim: title ?? "")
                .font(.subheadline.weight(.semibold))
                .lineLimit(lockupLines)
                .multilineTextAlignment(.leading)
            footer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondaryBackground)
    }
}

/// The platform line above a title: favicon and site name.
private struct Eyebrow: View {
    let item: LibraryItem
    let library: Library

    var body: some View {
        if item.modelContext != nil && !item.isDeleted {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 4) {
            if let icon = library.favicon(item) {
                Image(platformImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
                    .clipShape(.rect(cornerRadius: 3))
            } else {
                Image(systemName: item.isTextOnly ? "text.alignleft" : item.isImage ? "photo" : "globe")
            }
            Text(item.platformName)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}
