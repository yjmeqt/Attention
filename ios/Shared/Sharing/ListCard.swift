import SwiftUI

/// What a shared list's link preview shows: its first items as a feed. The title and count go in the page's
/// Open Graph tags, which apps that unfurl the link show beside the picture.
/// The preview is served as the list page's `og:image`, so pasting the link into Attention (or any app
/// that reads link previews) makes the list's picture without a separate share card (docs/list-sharing.md).
struct ListCardContent {
    struct Entry {
        let title: String
        let site: String
        let isText: Bool
        var image: PlatformImage?
        /// Width ÷ height of the photo, as the feed lays it out.
        var aspect: Double?
    }

    let title: String
    let count: Int
    let entries: [Entry]

    /// The preview shows the first items; more than this never fit in the square.
    static let entryLimit = 8

    /// From the items about to be uploaded.
    init(title: String, items: [LibraryItem], library: Library) {
        self.title = title
        self.count = items.count
        self.entries = items.prefix(Self.entryLimit).map { item in
            Entry(title: item.url != nil && !item.title.isEmpty ? item.title : item.displayTitle,
                  site: item.url != nil ? item.platformName : String(localized: "Text"),
                  isText: item.url == nil,
                  image: item.url != nil ? library.thumbnail(item) : nil,
                  aspect: item.thumbnailAspect > 0 ? item.thumbnailAspect : nil)
        }
    }

    init(title: String, count: Int, entries: [Entry]) {
        self.title = title
        self.count = count
        self.entries = entries
    }
}

/// The feed's background; the preview is drawn in dark mode, so it's black.
private let feedBackground = Color(.systemBackground)

/// The square link preview: the list's first items as a two-column feed, like the app's
/// feed and the web page, drawn with the feed's own tiles and colors. The feed runs off the bottom into the
/// background, which also gives the image a plain bottom edge, so Attention's card band under it comes out
/// clean. 360 pt, rendered at 3x (1080 px).
struct ListPreviewView: View {
    let content: ListCardContent

    static let side: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Only the feed: apps that unfurl the link already show the list's title and icon next to it.
            // It fills the square from the top; whatever doesn't fit is cut off.
            Color.clear
                .overlay(alignment: .top) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Self.lanes(content.entries), id: \.self) { lane in
                            VStack(spacing: 12) {
                                ForEach(lane, id: \.self) { tile(content.entries[$0]) }
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding([.horizontal, .top], 12)
                }
                .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [feedBackground.opacity(0), feedBackground],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 64)
            }
            feedBackground.frame(height: 10)
        }
        .frame(width: Self.side, height: Self.side)
        .background(feedBackground)
        .environment(\.dynamicTypeSize, .large)
        // Dark, like the app's feed at night: photos stand out, and the black edge gives Attention's card a dark band.
        .environment(\.colorScheme, .dark)
    }

    /// Entry indices per column, each tile going to the shorter one, as in the feed.
    static func lanes(_ entries: [ListCardContent.Entry]) -> [[Int]] {
        var lanes: [[Int]] = [[], []]
        var heights = [0.0, 0.0]
        for (index, entry) in entries.enumerated() {
            let lane = heights[0] <= heights[1] ? 0 : 1
            lanes[lane].append(index)
            heights[lane] += height(entry)
        }
        return lanes
    }

    /// In column widths, measured from rendered tiles: the photo by its aspect ratio, about 12 CJK or
    /// 22 Latin characters a line, the padding and site line, and the gap below.
    static func height(_ entry: ListCardContent.Entry) -> Double {
        let photo = entry.image != nil ? 1 / photoAspect(entry) : 0
        let limit = entry.isText ? 7 : (entry.image == nil ? 5 : 3)
        let width = entry.title.unicodeScalars.reduce(0.0) { $0 + ($1.isASCII ? 0.55 : 1) }
        let lines = min(limit, max(1, Int((width / 12).rounded(.up))))
        return photo + Double(lines) * 0.09 + 0.23
    }

    /// Width ÷ height, within the feed's range.
    static func photoAspect(_ entry: ListCardContent.Entry) -> Double {
        let natural = entry.image.map { Double($0.size.width / max($0.size.height, 1)) } ?? 1.33
        return min(max(entry.aspect ?? natural, Library.tileAspects.lowerBound), Library.tileAspects.upperBound)
    }

    /// The feed's own tile, with the site line the feed shows above the title.
    private func tile(_ entry: ListCardContent.Entry) -> some View {
        FeedTileFace(photo: entry.image, aspect: Self.photoAspect(entry), tint: entry.image.flatMap { CardTint($0) },
                     title: entry.title, lockupLines: entry.isText ? 7 : 5, fillsCell: false) {
            HStack(spacing: 4) {
                Image(systemName: entry.isText ? "text.alignleft" : "globe")
                Text(verbatim: entry.site).textCase(.uppercase).lineLimit(1)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        } footer: {
            EmptyView()
        }
    }
}

@MainActor
enum ListCardRenderer {
    /// The server takes square JPEGs 600–1200 px wide, up to 150 KB (web/src/listPreview.ts). Starts at
    /// 1080 px, lowering the quality, then the size. Nil when nothing fits, and the server uses its template.
    static func previewJPEG(_ content: ListCardContent) -> Data? {
        let renderer = ImageRenderer(content: ListPreviewView(content: content))
        renderer.proposedSize = ProposedViewSize(width: ListPreviewView.side, height: ListPreviewView.side)
        renderer.isOpaque = true
        for (scale, qualities) in [(3.0, [0.7, 0.6, 0.5]), (2.5, [0.6, 0.5, 0.4]), (2.0, [0.5, 0.4])] {
            renderer.scale = scale
            guard let image = renderer.cgImage else { continue }
            for quality in qualities {
                if let jpeg = ImageData.jpeg(image, quality: quality), jpeg.count <= 140 * 1024 { return jpeg }
            }
        }
        return nil
    }
}
