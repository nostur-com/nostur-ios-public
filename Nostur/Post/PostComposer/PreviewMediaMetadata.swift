import CryptoKit
import ImageIO
import Nuke
import UIKit
import UniformTypeIdentifiers

/// Uses completed preview downloads only. Metadata generation never fetches a URL.
enum PreviewMediaMetadata {
    // Bound metadata work across all images; it must never compete with UI
    // rendering by launching several thumbnail decodes at once.
    private static let workQueue = DispatchQueue(label: "com.nostur.preview-metadata", qos: .utility)

    @MainActor
    static func image(url: URL, response: ImageResponse, pipeline: ImagePipeline) async -> iMetaInfo {
        let cache = pipeline.configuration.dataCache
        let key = pipeline.cache.makeDataCacheKey(for: ImageRequest(url: url))
        let responseData = response.container.data
        let size = response.container.sourceDimensions
        return await generate(dimensions: size) {
            cache?.cachedData(for: key) ?? responseData
        }
    }

    static func generate(dimensions: CGSize, readData: @escaping @Sendable () -> Data?) async -> iMetaInfo {
        await withCheckedContinuation { continuation in
            workQueue.async {
                continuation.resume(returning: image(data: readData(), dimensions: dimensions))
            }
        }
    }

    static func image(data: Data?, dimensions: CGSize) -> iMetaInfo {
        var metadata = iMetaInfo(size: dimensions)
        guard let data else { return metadata }
        metadata.hash = hash(data)
        metadata.fileSize = data.count
        // Do not redraw the UIImage being displayed by SwiftUI. Read an
        // independent, bounded thumbnail from cached bytes on the worker queue.
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        if let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) {
            if let type = CGImageSourceGetType(source) {
                metadata.mimeType = UTType(type as String)?.preferredMIMEType
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 32
            ]
            if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                metadata.blurHash = UIImage(cgImage: thumbnail).blurHash(numberOfComponents: (4, 3))
            }
        }
        return metadata
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func tag(url: String, metadata: iMetaInfo) -> [String] {
        var parts = ["imeta", "url \(url)"]
        if let size = metadata.size, size.width.isFinite, size.height.isFinite,
           size.width > 0, size.height > 0, size.width < CGFloat(Int.max), size.height < CGFloat(Int.max) {
            parts.append("dim \(Int(size.width.rounded(.up)))x\(Int(size.height.rounded(.up)))")
        }
        if let hash = metadata.hash { parts.append("x \(hash)") }
        if let blurhash = metadata.blurHash, !blurhash.isEmpty { parts.append("blurhash \(blurhash)") }
        if let mimeType = metadata.mimeType { parts.append("m \(mimeType)") }
        if let size = metadata.fileSize { parts.append("size \(size)") }
        if let duration = metadata.duration { parts.append("duration \(duration)") }
        parts.append(contentsOf: metadata.fallbackURLs.map { "fallback \($0.absoluteString)" })
        return parts
    }
}
