//
//  NIP30CustomEmoji.swift
//  Nostur
//
//  Created by Codex on 12/04/2026.
//

import Foundation
import SwiftUI
import UIKit
import ImageIO

extension NSAttributedString.Key {
    static let nosturCustomEmojiURL = NSAttributedString.Key("nostur.customEmojiURL")
}

struct NIP30CustomEmoji {
    static let shortcodeRegex = try! NSRegularExpression(pattern: #":([A-Za-z0-9_-]+):"#, options: [])

    static func emojiMap(from fastTags: [FastTag]) -> [String: URL] {
        var map: [String: URL] = [:]

        for tag in fastTags where tag.0 == "emoji" {
            let shortcode = tag.1
            guard isValidShortcode(shortcode) else { continue }
            guard let urlString = tag.2, let url = URL(string: urlString) else { continue }
            map[shortcode] = url
        }

        return map
    }

    static func isValidShortcode(_ shortcode: String) -> Bool {
        guard !shortcode.isEmpty else { return false }
        return shortcode.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    static func containsRenderableShortcode(in text: String, emojiMap: [String: URL]) -> Bool {
        guard !emojiMap.isEmpty else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in shortcodeRegex.matches(in: text, options: [], range: range) {
            guard let shortcodeRange = Range(match.range(at: 1), in: text) else { continue }
            if emojiMap[String(text[shortcodeRange])] != nil {
                return true
            }
        }
        return false
    }

    static func exactShortcodeURL(content: String, fastTags: [FastTag]) -> URL? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = shortcodeRegex.firstMatch(in: trimmed, options: [], range: range) else { return nil }
        guard match.range.location == 0, match.range.length == range.length else { return nil }
        guard let shortcodeRange = Range(match.range(at: 1), in: trimmed) else { return nil }

        let shortcode = String(trimmed[shortcodeRange])
        return emojiMap(from: fastTags)[shortcode]
    }
}

final class NIP30CustomEmojiImageCache {
    static let shared = NIP30CustomEmojiImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 300
    }

    func image(for url: URL, pointSize: CGFloat) -> UIImage? {
        let key = "\(url.absoluteString)|\(Int(pointSize.rounded()))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        let scaled = scale(image: image, pointSize: pointSize)
        cache.setObject(scaled, forKey: key)
        return scaled
    }

    private func scale(image: UIImage, pointSize: CGFloat) -> UIImage {
        let src = image.size
        guard src.width > 0, src.height > 0 else { return image }

        let ratio = src.width / src.height
        let targetSize: CGSize
        if ratio >= 1 {
            targetSize = CGSize(width: pointSize, height: max(1, pointSize / ratio))
        }
        else {
            targetSize = CGSize(width: max(1, pointSize * ratio), height: pointSize)
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

struct NIP30ReactionContentView: View {
    let content: String?
    let fastTags: [FastTag]
    var size: CGFloat = 20

    private var trimmedContent: String {
        (content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        if trimmedContent.isEmpty || trimmedContent == "+" {
            Text("❤️")
        }
        else if let emojiURL = NIP30CustomEmoji.exactShortcodeURL(content: trimmedContent, fastTags: fastTags) {
            NIP30EmojiImage(url: emojiURL, size: size)
        }
        else {
            Text(trimmedContent)
        }
    }
}

struct NIP30EmojiImage: View {
    let url: URL
    let size: CGFloat
    var animate: Bool = true
    var onLoadedBytes: ((Int) -> Void)? = nil
    @State private var data: Data? = nil
    @State private var staticImage: UIImage? = nil
    @State private var loadFailed = false
    
    private static let gifHeader87a: [UInt8] = [0x47, 0x49, 0x46, 0x38, 0x37, 0x61]
    private static let gifHeader89a: [UInt8] = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]
    private static let maxEmojiBytes = 500_000
    private static let maxEmojiPixelDimension = 2048
    
    private var isAnimatedWebP: Bool {
        guard let data else { return false }
        return isAnimatedWebPData(data)
    }
    
    private var isGIF: Bool {
        guard let data, data.count >= 6 else { return false }
        let header = Array(data.prefix(6))
        return header == Self.gifHeader87a || header == Self.gifHeader89a
    }

    var body: some View {
        Group {
            if animate, let data, isAnimatedWebP {
                AnimatedWebPImage(data: data, isPlaying: .constant(true))
            }
            else if animate, let data, isGIF {
                GIFImage(data: data, isPlaying: .constant(true))
            }
            else if let staticImage {
                Image(uiImage: staticImage)
                    .resizable()
                    .scaledToFit()
            }
            else if loadFailed {
                Text("🫥")
            }
            else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task(id: url.absoluteString) {
            await loadEmojiData()
        }
        .frame(width: size, height: size)
        .clipped()
    }
    
    private func loadEmojiData() async {
        guard data == nil, !loadFailed else { return }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.cachePolicy = .returnCacheDataElseLoad

            let (data, response) = try await URLSession.shared.data(for: request)
            guard Self.isValidEmojiPayload(data: data, response: response) else {
                await MainActor.run {
                    self.loadFailed = true
                }
                return
            }

            let preview = await Self.makeThumbnailPreview(from: data, pointSize: size)
            await MainActor.run {
                self.data = data
                self.staticImage = preview
                self.onLoadedBytes?(data.count)
            }
        }
        catch {
            await MainActor.run {
                self.loadFailed = true
            }
        }
    }

    private static func isValidEmojiPayload(data: Data, response: URLResponse) -> Bool {
        guard !data.isEmpty, data.count <= maxEmojiBytes else { return false }

        if let httpResponse = response as? HTTPURLResponse,
           let mimeType = httpResponse.mimeType?.lowercased() {
            let isImage = mimeType.hasPrefix("image/")
            let isBinaryOctetStream = mimeType == "application/octet-stream"
            if !isImage && !isBinaryOctetStream { return false }
        }

        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        guard CGImageSourceGetCount(imageSource) > 0 else { return false }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else { return false }

        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard width > 0, height > 0 else { return false }
        guard width <= maxEmojiPixelDimension, height <= maxEmojiPixelDimension else { return false }
        return true
    }

    private static func makeThumbnailPreview(from data: Data, pointSize: CGFloat) async -> UIImage? {
        let screenScale = UIScreen.main.scale
        return await Task.detached(priority: .utility) { () -> UIImage? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let pixelSize = max(Int(pointSize * screenScale * 2.0), 1)
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: false,
                kCGImageSourceThumbnailMaxPixelSize: pixelSize
            ]
            guard let imageRef = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: imageRef)
        }.value
    }
}
