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
        let _ = library.revision
        Group {
            if let photo = library.thumbnail(item) {
                card(photo)
            } else {
                lockup
            }
        }
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator.opacity(0.4), lineWidth: 0.5)
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

    /// A photo with a band below it in the photo's own color, like App Store Today cards.
    private func card(_ photo: UIImage) -> some View {
        let tint = library.tint(item)
        return VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(item.thumbnailAspect, contentMode: .fit)
                .overlay { Image(uiImage: photo).resizable().scaledToFill() }
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(item: item, library: library)
                if !item.isImage || !item.title.isEmpty {
                    Text(item.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                footer
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.map { Color(uiColor: $0.color) } ?? Color(.secondarySystemBackground))
            .environment(\.colorScheme, tint.map { $0.isDark ? .dark : .light } ?? colorScheme)
        }
    }

    /// Links without a photo look like an App Store app row: icon, name and an Open button.
    private var lockup: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Group {
                    if let icon = library.favicon(item) {
                        Image(uiImage: icon).resizable().scaledToFill()
                    } else {
                        Image(systemName: item.isImage ? "photo" : "globe")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.fill.tertiary)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.platformName)
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(item.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
            }
            HStack {
                footer
                Spacer(minLength: 4)
                if let onOpen, !item.isImage {
                    Button("Open", action: onOpen)
                        .font(.caption.weight(.bold))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
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

    @Environment(\.colorScheme) private var colorScheme
}

/// The platform line above a title: favicon and site name.
private struct Eyebrow: View {
    let item: LibraryItem
    let library: Library

    var body: some View {
        HStack(spacing: 4) {
            if let icon = library.favicon(item) {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
                    .clipShape(.rect(cornerRadius: 3))
            } else {
                Image(systemName: item.isImage ? "photo" : "globe")
            }
            Text(item.platformName)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

/// Shrinks a little while pressed, like App Store cards.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

struct FilterBar: View {
    @Bindable var filter: FeedFilter
    let items: [LibraryItem]
    let onPrivate: () -> Void

    var body: some View {
        let section = filter.section(items)
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(String(localized: "All"), selected: filter.domains.isEmpty && filter.tags.isEmpty && !filter.showsPrivate) {
                    filter.reset()
                }
                ForEach(Self.ranked(section.map(\.domain)), id: \.self) { domain in
                    chip(DomainTag.label(domain), selected: filter.domains.contains(domain)) {
                        toggle(domain, in: \.domains)
                    }
                }
                ForEach(Self.ranked(section.flatMap(\.tags)), id: \.self) { tag in
                    chip("#\(tag)", selected: filter.tags.contains(tag)) {
                        toggle(tag, in: \.tags)
                    }
                }
                chip(String(localized: "Private"), systemImage: "lock.fill", selected: filter.showsPrivate) {
                    if filter.showsPrivate { filter.reset() } else { onPrivate() }
                }
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ text: String, systemImage: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TagChip(text: text, systemImage: systemImage, isSelected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggle(_ value: String, in keyPath: ReferenceWritableKeyPath<FeedFilter, Set<String>>) {
        if filter[keyPath: keyPath].contains(value) {
            filter[keyPath: keyPath].remove(value)
        } else {
            filter[keyPath: keyPath].insert(value)
        }
    }

    /// Most common first.
    static func ranked(_ values: [String]) -> [String] {
        let counts = values.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }
}
