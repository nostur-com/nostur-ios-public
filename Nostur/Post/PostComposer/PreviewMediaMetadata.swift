import CryptoKit
import ImageIO
import Nuke
import UIKit
import UniformTypeIdentifiers

/// Uses completed preview downloads only. Metadata generation never fetches a URL.
enum PreviewMediaMetadata {
    @MainActor
    static func image(url: URL, response: ImageResponse, pipeline: ImagePipeline) async -> iMetaInfo {
        let cache = pipeline.configuration.dataCache
        let key = pipeline.cache.makeDataCacheKey(for: ImageRequest(url: url))
        let responseData = response.container.data
        let renderedImage = response.image
        let size = response.container.sourceDimensions
        return await Task.detached(priority: .utility) {
            let data = cache?.cachedData(for: key) ?? responseData
            return image(data: data, renderedImage: renderedImage, dimensions: size)
        }.value
    }

    static func image(data: Data?, renderedImage: UIImage, dimensions: CGSize) -> iMetaInfo {
        var metadata = iMetaInfo(size: dimensions, blurHash: blurhash(renderedImage))
        guard let data else { return metadata }
        metadata.hash = hash(data)
        metadata.fileSize = data.count
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
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

    private static func blurhash(_ image: UIImage) -> String? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, 32 / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return thumbnail.blurHash(numberOfComponents: (4, 3))
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
