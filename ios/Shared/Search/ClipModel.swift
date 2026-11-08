#if os(iOS)
import Foundation
import CoreML
import CryptoKit
import AppleArchive
import System
import Observation
import UIKit

/// On-demand MobileCLIP-S0: downloads once, embeds images and text for visual search.
@Observable
@MainActor
final class ClipModel {
    static let shared = ClipModel()

    enum Status: Equatable {
        case missing, downloading(Double), ready, failed(String)
    }

    private(set) var status: Status = .missing

    /// Cosine similarity above this counts as a visual match. Tuned against demo covers.
    static let matchThreshold: Float = 0.22
    static let embeddingDimensions = 512
    static let imageSize = CGSize(width: 256, height: 256)

    /// GitHub release first; mirrors help when github.com is slow or blocked.
    static let archiveURLs: [URL] = [
        URL(string: "https://github.com/yjmeqt/Attention/releases/download/mobileclip-s0-v1/mobileclip-s0.aar")!,
        URL(string: "https://ghfast.top/https://github.com/yjmeqt/Attention/releases/download/mobileclip-s0-v1/mobileclip-s0.aar")!,
        URL(string: "https://mirror.ghproxy.com/https://github.com/yjmeqt/Attention/releases/download/mobileclip-s0-v1/mobileclip-s0.aar")!,
    ]
    static let archiveURL = archiveURLs[0]
    /// Filled by `ios/Tools/mobileclip/package.zsh` after it builds the archive.
    static let archiveSHA256 = "096d73559ed998a84eb5db594f9f857a84293ce1f279093397fc3f72ab969feb"

    private let directory: URL
    private var imageModel: MLModel?
    private var textModel: MLModel?
    private var tokenizer: CLIPTokenizer?
    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?
    private var downloadIndex = 0
    private let session = URLSession(configuration: .default)

    init(directory: URL = AppGroup.container.appending(path: "MobileCLIP", directoryHint: .isDirectory)) {
        self.directory = directory
        if FileManager.default.fileExists(atPath: directory.appending(path: "mobileclip_s0_image.mlmodelc").path) {
            Task { await load() }
        }
    }

    var isReady: Bool {
        if case .ready = status { return true }
        return false
    }

    func download() {
        switch status {
        case .downloading, .ready: return
        case .missing, .failed: break
        }
        downloadIndex = 0
        status = .downloading(0)
        startDownload(at: 0)
    }

    private func startDownload(at index: Int) {
        guard Self.archiveURLs.indices.contains(index) else {
            status = .failed(String(localized: "Couldn't reach GitHub to download the model. Check your network or try again on Wi‑Fi."))
            return
        }
        downloadIndex = index
        let url = Self.archiveURLs[index]
        let task = session.downloadTask(with: url) { [weak self] temp, response, error in
            Task { @MainActor in
                guard let self else { return }
                self.progressObservation = nil
                self.downloadTask = nil
                if let error {
                    if (error as? URLError)?.code == .cancelled {
                        if case .missing = self.status { return }
                        return
                    }
                    self.retryOrFail(Self.message(for: error))
                    return
                }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    self.retryOrFail(String(localized: "Download failed (HTTP \(http.statusCode))."))
                    return
                }
                guard let temp else {
                    self.retryOrFail(String(localized: "Download failed."))
                    return
                }
                do {
                    try self.install(from: temp)
                    await self.load()
                } catch {
                    // Checksum / extract failures are about the file itself — don't burn mirrors on a bad build.
                    self.status = .failed(error.localizedDescription)
                    try? FileManager.default.removeItem(at: self.directory)
                }
            }
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor in self?.status = .downloading(progress.fractionCompleted) }
        }
        downloadTask = task
        task.resume()
    }

    private func retryOrFail(_ message: String) {
        let next = downloadIndex + 1
        if Self.archiveURLs.indices.contains(next) {
            status = .downloading(0)
            startDownload(at: next)
        } else {
            status = .failed(message)
        }
    }

    private static func message(for error: Error) -> String {
        let urlError = error as? URLError
        switch urlError?.code {
        case .notConnectedToInternet:
            return String(localized: "No Internet connection.")
        case .timedOut:
            return String(localized: "The download timed out. GitHub can be slow in some regions — try again.")
        case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost:
            return String(localized: "Couldn't reach the download server. GitHub may be blocked on this network.")
        case .networkConnectionLost:
            return String(localized: "The connection dropped. Try again on a more stable network.")
        default:
            return error.localizedDescription
        }
    }

    func delete() {
        downloadTask?.cancel()
        progressObservation = nil
        downloadTask = nil
        imageModel = nil
        textModel = nil
        tokenizer = nil
        try? FileManager.default.removeItem(at: directory)
        status = .missing
    }

    /// L2-normalized 512-d embedding of a JPEG/PNG, or nil if the model isn't ready.
    func imageEmbedding(data: Data) async -> [Float]? {
        guard let imageModel, let cgImage = ImageData.downsample(data, maxPixel: 512) else { return nil }
        guard let buffer = Self.pixelBuffer(cgImage, size: Self.imageSize) else { return nil }
        return embed(image: buffer, model: imageModel)
    }

    /// L2-normalized 512-d embedding of a text prompt (English works best).
    func textEmbedding(_ text: String) async -> [Float]? {
        guard let textModel, let tokenizer else { return nil }
        let ids = tokenizer.encodeFull(text)
        guard let input = try? MLMultiArray(shape: [1, 77], dataType: .int32) else { return nil }
        for (i, id) in ids.enumerated() { input[i] = NSNumber(value: id) }
        return embed(text: input, model: textModel)
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        for i in a.indices { dot += a[i] * b[i] }
        return dot
    }

    // MARK: - Private

    private func load() async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            imageModel = try await MLModel.load(contentsOf: directory.appending(path: "mobileclip_s0_image.mlmodelc"), configuration: config)
            textModel = try await MLModel.load(contentsOf: directory.appending(path: "mobileclip_s0_text.mlmodelc"), configuration: config)
            tokenizer = try CLIPTokenizer(directory: directory)
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func install(from archive: URL) throws {
        let data = try Data(contentsOf: archive)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == Self.archiveSHA256 else {
            throw ClipError.checksumMismatch
        }
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.extract(archive: archive, to: directory)
    }

    private static func extract(archive: URL, to destination: URL) throws {
        let archivePath = FilePath(archive.path)
        let destPath = FilePath(destination.path)
        guard let readFile = ArchiveByteStream.fileStream(
                path: archivePath, mode: .readOnly, options: [],
                permissions: FilePermissions(rawValue: 0o644)),
              let decompress = ArchiveByteStream.decompressionStream(readingFrom: readFile),
              let decode = ArchiveStream.decodeStream(readingFrom: decompress),
              let extract = ArchiveStream.extractStream(extractingTo: destPath, flags: [.ignoreOperationNotPermitted])
        else { throw ClipError.extractFailed }
        defer {
            try? extract.close()
            try? decode.close()
            try? decompress.close()
            try? readFile.close()
        }
        _ = try ArchiveStream.process(readingFrom: decode, writingTo: extract)
    }

    private func embed(image buffer: CVPixelBuffer, model: MLModel) -> [Float]? {
        let provider = try? MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: buffer)])
        guard let provider, let out = try? model.prediction(from: provider),
              let array = out.featureValue(for: "final_emb_1")?.multiArrayValue
        else { return nil }
        return Self.normalized(array)
    }

    private func embed(text input: MLMultiArray, model: MLModel) -> [Float]? {
        let provider = try? MLDictionaryFeatureProvider(dictionary: ["text": MLFeatureValue(multiArray: input)])
        guard let provider, let out = try? model.prediction(from: provider),
              let array = out.featureValue(for: "final_emb_1")?.multiArrayValue
        else { return nil }
        return Self.normalized(array)
    }

    private static func normalized(_ array: MLMultiArray) -> [Float] {
        let count = array.count
        var values = [Float](repeating: 0, count: count)
        for i in 0..<count { values[i] = array[i].floatValue }
        let norm = sqrt(values.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return values }
        return values.map { $0 / norm }
    }

    private static func pixelBuffer(_ image: CGImage, size: CGSize) -> CVPixelBuffer? {
        let width = Int(size.width), height = Int(size.height)
        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attrs as CFDictionary, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        let side = min(image.width, image.height)
        let originX = (image.width - side) / 2
        let originY = (image.height - side) / 2
        if let cropped = image.cropping(to: CGRect(x: originX, y: originY, width: side, height: side)) {
            context.interpolationQuality = .high
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return buffer
    }
}

enum ClipError: LocalizedError {
    case checksumMismatch, extractFailed
    var errorDescription: String? {
        switch self {
        case .checksumMismatch: String(localized: "The downloaded model didn't match what was expected.")
        case .extractFailed: String(localized: "Couldn't unpack the model.")
        }
    }
}
#endif
