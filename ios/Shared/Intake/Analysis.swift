import Foundation

extension Library {
    /// `analysisVersion` values: Vision labels only, or labels plus model keywords.
    enum Analysis {
        static let labels = 1
        static let keywords = 2

        /// Devices without Apple Intelligence stop at labels; ones with it add keywords to items analyzed elsewhere.
        static var target: Int { KeywordWriter.isAvailable ? keywords : labels }
    }

    /// Labels and keywords the item's image and text, so search can find it by what's in it.
    func analyze(_ item: LibraryItem) async {
        let image = item.isImage ? data(.source, of: item) : coverData(item)
        let labels = if let image { await ImageAnalysis.labels(for: image) } else { [String]() }
        item.visualLabels = labels
        if let keywords = await KeywordWriter.keywords(site: item.platformName, title: item.title, text: item.ocrText, labels: labels) {
            item.keywords = keywords
            item.analysisVersion = Analysis.keywords
        } else {
            item.analysisVersion = Analysis.labels
        }
    }

    #if !SHARE_EXTENSION
    /// Analyzes items saved or changed since their last analysis, a few at a time. Not in the share
    /// extension, which has little memory to spare; the app catches up on what it saved.
    func analyzePending() async {
        guard !analyzing else { return }
        analyzing = true
        defer { analyzing = false }
        while true {
            let target = Analysis.target
            let batch = items.filter { $0.analysisVersion < target && !enriching.contains($0.id) }.prefix(8)
            guard !batch.isEmpty else { return }
            for item in batch { await analyze(item) }
            save()
        }
    }
    #endif
}
