import SwiftUI
import UIKit

/// The feed as a `UICollectionView`: a staggered layout that places each tile by its real height,
/// a diffable data source keyed by item id, and SwiftUI tiles hosted in reused cells.
struct FeedCollection<Tile: View, Header: View>: UIViewRepresentable {
    let items: [LibraryItem]
    let columns: Int
    /// Bumped when tiles need to be rebuilt without the item list changing, e.g. selection.
    let tileRevision: Int
    var onSelect: (LibraryItem) -> Void
    var onScroll: (CGFloat) -> Void
    @ViewBuilder let tile: (LibraryItem, Bool) -> Tile
    /// Scrolls with the tiles above them, sized to its own height.
    @ViewBuilder let header: () -> Header

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UICollectionView {
        let coordinator = context.coordinator
        let layout = StaggeredLayout()
        layout.height = { [unowned coordinator] index, width in coordinator.height(at: index, width: width) }
        coordinator.layout = layout
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.showsHorizontalScrollIndicator = false
        view.topEdgeEffect.isHidden = true
        view.bottomEdgeEffect.isHidden = true
        view.delegate = coordinator
        let registration = UICollectionView.CellRegistration<UICollectionViewCell, UUID> { [unowned coordinator] cell, _, id in
            cell.configurationUpdateHandler = { [unowned coordinator] cell, state in
                guard let item = coordinator.byID[id], let tile = coordinator.tile else { return }
                cell.contentConfiguration = UIHostingConfiguration { tile(item, state.isHighlighted) }
                    .margins(.all, 0)
            }
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(
            elementKind: StaggeredLayout.headerKind
        ) { [unowned coordinator] cell, _, _ in
            coordinator.configureHeader(cell)
        }
        coordinator.dataSource = UICollectionViewDiffableDataSource(collectionView: view) { view, indexPath, id in
            view.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
        }
        coordinator.dataSource.supplementaryViewProvider = { view, _, indexPath in
            view.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        coordinator.tile = { AnyView(tile($0, $1)) }
        coordinator.header = AnyView(header())
        if let cell = view.supplementaryView(forElementKind: StaggeredLayout.headerKind, at: IndexPath(item: 0, section: 0)) as? UICollectionViewCell {
            coordinator.configureHeader(cell)
        }
        coordinator.onSelect = onSelect
        coordinator.onScroll = onScroll
        let layout = view.collectionViewLayout as! StaggeredLayout
        let ids = items.map(\.id)
        let reorder = ids != coordinator.ids
        coordinator.items = items
        coordinator.byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if layout.columns != columns {
            layout.columns = columns
            layout.invalidateLayout()
        }
        if reorder {
            coordinator.ids = ids
            var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
            snapshot.appendSections([0])
            snapshot.appendItems(ids)
            coordinator.dataSource.apply(snapshot, animatingDifferences: view.window != nil)
        } else {
            layout.invalidateLayout()
            if coordinator.tileRevision != tileRevision {
                var snapshot = coordinator.dataSource.snapshot()
                snapshot.reconfigureItems(view.indexPathsForVisibleItems.compactMap { coordinator.dataSource.itemIdentifier(for: $0) })
                coordinator.dataSource.apply(snapshot, animatingDifferences: false)
            }
        }
        coordinator.tileRevision = tileRevision
    }

    final class Coordinator: NSObject, UICollectionViewDelegate {
        var dataSource: UICollectionViewDiffableDataSource<Int, UUID>!
        var items: [LibraryItem] = []
        var ids: [UUID] = []
        var byID: [UUID: LibraryItem] = [:]
        var tileRevision = 0
        var tile: ((LibraryItem, Bool) -> AnyView)?
        var header: AnyView?
        weak var layout: StaggeredLayout?
        var onSelect: (LibraryItem) -> Void = { _ in }
        var onScroll: (CGFloat) -> Void = { _ in }
        private var heights: [HeightKey: CGFloat] = [:]

        /// The header reports its ideal height, which the layout then gives it; a tip that
        /// appears or is closed later moves the tiles with it.
        func configureHeader(_ cell: UICollectionViewCell) {
            cell.contentConfiguration = UIHostingConfiguration {
                (header ?? AnyView(EmptyView()))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { [weak self] height in
                        self?.headerHeightChanged(height)
                    }
            }
            .margins(.all, 0)
        }

        private func headerHeightChanged(_ height: CGFloat) {
            guard let layout, abs(layout.headerHeight - height) > 0.5 else { return }
            DispatchQueue.main.async {
                layout.headerHeight = height
                layout.invalidateLayout()
            }
        }

        private struct HeightKey: Hashable {
            let id: UUID
            let title: String
            let aspect: Double
            let width: CGFloat
        }

        func height(at index: Int, width: CGFloat) -> CGFloat {
            guard items.indices.contains(index) else { return 0 }
            let item = items[index]
            let key = HeightKey(id: item.id, title: item.displayTitle, aspect: item.thumbnailAspect, width: width)
            if let cached = heights[key] { return cached }
            let height = TileMetrics.height(of: item, width: width)
            heights[key] = height
            return height
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath, animated: false)
            if let id = dataSource.itemIdentifier(for: indexPath), let item = byID[id] { onSelect(item) }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            onScroll(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
        }
    }
}

/// Places each item in the currently shortest column, using its measured height.
final class StaggeredLayout: UICollectionViewLayout {
    static let headerKind = "header"
    var columns = 2
    var spacing: CGFloat = 12
    var inset = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
    /// Kept at least a point tall so an empty header is still laid out and can report a new height.
    var headerHeight: CGFloat = 0
    var height: (Int, CGFloat) -> CGFloat = { _, _ in 0 }
    private var attributes: [UICollectionViewLayoutAttributes] = []
    private var headerAttributes: UICollectionViewLayoutAttributes?
    private var contentHeight: CGFloat = 0
    private var preparedWidth: CGFloat = 0

    override func prepare() {
        guard let view = collectionView else { return }
        let hasSection = view.numberOfSections > 0
        let count = hasSection ? view.numberOfItems(inSection: 0) : 0
        preparedWidth = view.bounds.width
        let width = floor((view.bounds.width - inset.left - inset.right - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        var top = inset.top
        headerAttributes = nil
        if hasSection {
            let header = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: Self.headerKind, with: IndexPath(item: 0, section: 0))
            header.frame = CGRect(x: 0, y: inset.top, width: view.bounds.width, height: max(headerHeight, 1))
            headerAttributes = header
            if headerHeight > 1 { top += headerHeight + spacing }
        }
        var bottoms = Array(repeating: top, count: columns)
        attributes = (0..<count).map { index in
            let column = bottoms.indices.min { bottoms[$0] < bottoms[$1] } ?? 0
            let frame = CGRect(x: inset.left + CGFloat(column) * (width + spacing), y: bottoms[column],
                               width: width, height: height(index, width))
            bottoms[column] = frame.maxY + spacing
            let attribute = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: index, section: 0))
            attribute.frame = frame
            return attribute
        }
        contentHeight = (bottoms.max() ?? 0) - spacing + inset.bottom
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: collectionView?.bounds.width ?? 0, height: contentHeight)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let tiles = attributes.filter { $0.frame.intersects(rect) }
        guard let headerAttributes, headerAttributes.frame.intersects(rect) else { return tiles }
        return [headerAttributes] + tiles
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        attributes.indices.contains(indexPath.item) ? attributes[indexPath.item] : nil
    }

    override func layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        elementKind == Self.headerKind ? headerAttributes : nil
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.width != preparedWidth
    }
}

/// A tile's height without building it: the photo at its aspect ratio over the text band, whose
/// fixed parts are measured once from the same SwiftUI views and whose title is measured with TextKit.
enum TileMetrics {
    @MainActor private static var bands: [UIContentSizeCategory: CGFloat] = [:]

    static func height(of item: LibraryItem, width: CGFloat) -> CGFloat {
        let photo = item.thumbnailAspect > 0 ? (width / item.thumbnailAspect).rounded(.up) : 0
        let showsTitle = photo == 0 || !item.isImage || !item.title.isEmpty
        let title = showsTitle ? titleHeight(item.displayTitle, width: width - 20, lines: photo > 0 ? 3 : 6) + 4 : 0
        return photo + band() + title
    }

    private static func band() -> CGFloat {
        let category = UITraitCollection.current.preferredContentSizeCategory
        if let band = bands[category] { return band }
        let probe = UIHostingController(rootView: BandProbe())
        let band = probe.sizeThatFits(in: CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)).height
        bands[category] = band
        return band
    }

    private static func titleHeight(_ title: String, width: CGFloat, lines: Int) -> CGFloat {
        let base = UIFont.preferredFont(forTextStyle: .subheadline)
        let font = UIFont.systemFont(ofSize: base.pointSize, weight: .semibold)
        let full = (title as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                    attributes: [.font: font], context: nil).height
        return min(ceil(full), ceil(font.lineHeight * CGFloat(lines)))
    }

    /// The band's eyebrow and footer rows with no title, laid out as in `FeedTile`.
    private struct BandProbe: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "globe").frame(width: 14, height: 14)
                    Text(verbatim: "SITE")
                }
                .font(.caption2.weight(.semibold))
                HStack {
                    Text(verbatim: "1h").font(.caption2)
                    Spacer(minLength: 4)
                    Button("Open") {}
                        .font(.caption.weight(.bold))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                }
            }
            .padding(10)
        }
    }
}
