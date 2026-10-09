import AVFoundation
import Combine
import CryptoKit
import ImageIO
import NostrEssentials
import UIKit

/// Metadata for the file served by Blossom, which can differ from the uploaded file.
struct BlossomPostMetadata: Sendable {
    var hash: String?
    var dim: String?
    var blurhash: String?

    init(hash: String? = nil, dim: String? = nil, blurhash: String? = nil) {
        self.hash = hash?.isEmpty == false ? hash : nil
        self.dim = dim?.isEmpty == false && dim != "0x0" ? dim : nil
        self.blurhash = blurhash?.isEmpty == false ? blurhash : nil
    }

    func needsDownload(contentType: String) -> Bool {
        hash == nil || (isVisual(contentType) && (dim == nil || blurhash == nil))
    }

    private func isVisual(_ contentType: String) -> Bool {
        contentType.hasPrefix("image/") || contentType.hasPrefix("video/")
    }

    /// Keep I/O, hashing, and thumbnail decoding off the main actor.
    func completing(
        from url: URL,
        contentType: String,
        download: @escaping @Sendable (URLRequest) async throws -> (URL, URLResponse) = { try await URLSession.shared.download(for: $0) }
    ) async throws -> Self {
        guard needsDownload(contentType: contentType) else { return self }
        let task = Task.detached(priority: .utility) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            let (file, response) = try await download(request)
            defer { try? FileManager.default.removeItem(at: file) }
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw URLError(.badServerResponse)
            }
            try Task.checkCancellation()
            return try await fillingMissingFields(from: file, contentType: contentType)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func fillingMissingFields(from file: URL, contentType: String) async throws -> Self {
        var result = self
        if result.hash == nil {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var hash = SHA256()
            while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                try Task.checkCancellation()
                hash.update(data: chunk)
            }
            result.hash = Data(hash.finalize()).hexEncodedString()
        }
        guard isVisual(contentType), result.dim == nil || result.blurhash == nil else { return result }

        if let source = CGImageSourceCreateWithURL(file as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            if result.dim == nil,
               let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
               let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
               width.intValue > 0, height.intValue > 0 {
                let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
                result.dim = (5...8).contains(orientation)
                    ? "\(height.intValue)x\(width.intValue)"
                    : "\(width.intValue)x\(height.intValue)"
            }
            if result.blurhash == nil {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 32
                ]
                if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                    result.blurhash = UIImage(cgImage: thumbnail).blurHash(numberOfComponents: (4, 3))
                }
            }
        }
        else if contentType.hasPrefix("video/") {
            let asset = AVURLAsset(url: file)
            if result.dim == nil, let size = await getVideoDimensions(asset: asset), size.width > 0, size.height > 0 {
                result.dim = "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
            }
            if result.blurhash == nil {
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 32, height: 32)
                let thumbnail: CGImage
                if #available(iOS 16.0, *) {
                    thumbnail = try await generator.image(at: .zero).image
                }
                else {
                    thumbnail = try generator.copyCGImage(at: .zero, actualTime: nil)
                }
                result.blurhash = UIImage(cgImage: thumbnail).blurHash(numberOfComponents: (4, 3))
            }
        }
        guard result.dim != nil, result.blurhash != nil else { throw URLError(.cannotDecodeContentData) }
        return result
    }
}

/// The library's upload decoder requires sha256; accept an omitted hash here so
/// post metadata can instead be calculated from the returned file.
struct BlossomPostUploadResponse: Decodable {
    let url: String
    var sha256: String?
    var type: String?
    var nip94: [NostrEssentials.Tag]?

    var downloadURL: String {
        tagValue("url") ?? url
    }

    var metadata: BlossomPostMetadata {
        return BlossomPostMetadata(
            hash: tagValue("x") ?? sha256,
            dim: tagValue("dim"),
            blurhash: tagValue("blurhash")
        )
    }

    private func tagValue(_ type: String) -> String? {
        guard let value = nip94?.first(where: { $0.type == type && $0.tag.count > 1 })?.value, !value.isEmpty else { return nil }
        return value
    }
}

@MainActor
func completeBlossomPostUpload(
    _ item: BlossomUploadItem,
    response: BlossomPostUploadResponse,
    download: @escaping @Sendable (URLRequest) async throws -> (URL, URLResponse) = { try await URLSession.shared.download(for: $0) }
) async throws {
    guard let url = URL(string: response.downloadURL), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
        throw URLError(.badURL)
    }
    let serverType = response.type ?? ""
    let contentType = ["image/", "video/", "audio/"].contains(where: { serverType.hasPrefix($0) })
        ? serverType : (item.contentType ?? "application/octet-stream")
    if response.metadata.needsDownload(contentType: contentType) {
        item.state = .processing(percentage: 0)
    }
    let completed = try await response.metadata.completing(from: url, contentType: contentType, download: download)
    try Task.checkCancellation()
    item.sha256processed = completed.hash
    item.dim = completed.dim
    item.blurhash = completed.blurhash
    item.downloadUrl = response.downloadURL
    item.state = .success(response.downloadURL)
}

/// Complete metadata before emitting a successful upload to the composer.
func uploadBlossomPostPublisher(for item: BlossomUploadItem, server: URL) -> AnyPublisher<BlossomUploadItem, Error> {
    Deferred {
        var task: Task<Void, Never>?
        let future = Future<BlossomUploadItem, Error> { promise in
            task = Task { @MainActor in
                do {
                    item.state = .uploading(percentage: 0)
                    var request = URLRequest(url: server.appendingPathComponent(item.verb == .media ? "media" : "upload"))
                    request.httpMethod = "PUT"
                    request.setValue(item.contentType, forHTTPHeaderField: "Content-Type")
                    request.setValue(item.authorizationHeader, forHTTPHeaderField: "Authorization")
                    request.setValue(item.sha256, forHTTPHeaderField: "X-SHA-256")
                    request.httpBody = item.mediaData
                    let session = URLSession(configuration: .default, delegate: item, delegateQueue: nil)
                    defer { session.finishTasksAndInvalidate() }
                    let (data, response) = try await session.data(for: request)
                    guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    switch response.statusCode {
                    case 200, 201, 202: break
                    case 401, 403: throw URLError(.userAuthenticationRequired)
                    default: throw URLError(.badServerResponse)
                    }
                    let result = try JSONDecoder().decode(BlossomPostUploadResponse.self, from: data)
                    try await completeBlossomPostUpload(item, response: result)
                    promise(.success(item))
                }
                catch {
                    item.state = .error(message: error.localizedDescription)
                    promise(.failure(error))
                }
            }
        }
        return future.handleEvents(receiveCancel: { task?.cancel() }).eraseToAnyPublisher()
    }
    .eraseToAnyPublisher()
}
