import Foundation
import CryptoKit

extension Library {
    enum Analysis {
        static let labels = 1
        static let keywords = 2
        static var target: Int { KeywordWriter.isAvailable ? keywords : labels }
    }

    typealias KeywordGenerator = (String, String, String?, [String]) async -> [String]?

    func searchImage(_ item: LibraryItem) -> Data? {
        item.isImage ? data(.source, of: item) : coverData(item)
    }

    /// Includes synced content, so caches are rejected even when another device made the edit.
    func analysisFingerprint(_ item: LibraryItem) -> String {
        let text = [item.platformName, item.title, item.text ?? "", item.ocrText ?? ""]
        var bytes = (try? JSONEncoder().encode(text)) ?? Data()
        bytes.append(Data(SHA256.hash(data: searchImage(item) ?? Data())))
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    func invalidateAnalysis(_ item: LibraryItem) {
        item.analysisVersion = 0
        item.analysisFingerprint = ""
        item.visualLabels = []
        item.keywords = []
        analysisFailures[item.id] = nil
        write(nil, .embedding, of: item)
        #if !SHARE_EXTENSION
        scheduleAnalysis()
        #endif
    }

    func analyze(_ item: LibraryItem, writeKeywords: KeywordGenerator = KeywordWriter.keywords) async {
        guard !Task.isCancelled, contains(item) else { return }
        let fingerprint = analysisFingerprint(item)
        let image = searchImage(item)
        let site = item.platformName
        let title = item.title
        let text = [item.text, item.ocrText].compactMap { $0 }.joined(separator: "\n")
        let labels = if let image { await ImageAnalysis.labels(for: image) } else { [String]() }
        guard !Task.isCancelled, contains(item), fingerprint == analysisFingerprint(item) else { return }
        let keywords = await writeKeywords(site, title, text, labels)
        guard !Task.isCancelled, contains(item), fingerprint == analysisFingerprint(item) else { return }
        item.visualLabels = labels
        item.keywords = keywords ?? []
        item.analysisVersion = keywords == nil ? Analysis.labels : Analysis.keywords
        item.analysisFingerprint = fingerprint
        if keywords == nil {
            let old = analysisFailures[item.id]
            analysisFailures[item.id] = (fingerprint, (old?.fingerprint == fingerprint ? old!.count : 0) + 1)
        } else {
            analysisFailures[item.id] = nil
        }
    }

    #if !SHARE_EXTENSION
    /// Coalesce edits; a running pass sees the new fingerprint and rejects stale work.
    func scheduleAnalysis() {
        analysisRequested = true
        guard pendingAnalysis == nil else { return }
        pendingAnalysis = Task { [weak self] in
            guard let self else { return }
            defer { self.pendingAnalysis = nil }
            while self.analysisRequested && !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                // Another pass may still be awaiting a model. Keep the edit queued.
                guard !self.analyzing else { continue }
                self.analysisRequested = false
                await self.analyzePending()
            }
        }
    }

    /// One attempt per item per pass, at most three failures for unchanged content per launch.
    /// A later activation/edit can retry without busy-looping on a broken model.
    func analyzePending(target requestedTarget: Int? = nil,
                        writeKeywords: KeywordGenerator = KeywordWriter.keywords) async {
        guard !analyzing else { return }
        analyzing = true
        defer { analyzing = false }
        let target = requestedTarget ?? Analysis.target
        // Snapshot once. Edits/new captures schedule another pass; don't re-hash the
        // entire image library for every small batch while migrating old indexes.
        let pending = items
        var completed = 0
        for item in pending {
            guard !Task.isCancelled else { return }
            guard contains(item), !enriching.contains(item.id) else { continue }
            let fingerprint = analysisFingerprint(item)
            let failure = analysisFailures[item.id]
            guard failure?.fingerprint != fingerprint || (failure?.count ?? 0) < 3 else { continue }
            guard item.analysisVersion < target || item.analysisFingerprint != fingerprint else { continue }
            await analyze(item, writeKeywords: writeKeywords)
            completed += 1
            if completed % 8 == 0 { save() }
        }
        if completed % 8 != 0 { save() }
        #if os(iOS)
        await embedPending()
        #endif
    }
    #endif
}
