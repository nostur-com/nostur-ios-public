import AVFoundation
import Combine
import ImageIO
import NostrEssentials
import UIKit

/// BUD-01 addresses are known before BUD-04 mirroring finishes. Publishing
/// these NIP-92 candidates never waits for mirror network requests.
struct BlossomPostMirrorPlan: Sendable {
    let sourceURL: URL
    let hash: String
    let servers: [URL]
    let fallbackURLs: [String]

    init?(sourceURL: String, hash: String?, serverStrings: [String]) {
        guard let source = URL(string: sourceURL),
              let hash, hash.count == 64, hash.allSatisfy({ $0.isHexDigit })
        else { return nil }
        self.sourceURL = source
        self.hash = hash.lowercased()
        var seen = Set<String>()
        let roots = serverStrings.compactMap { value -> URL? in
            guard var components = URLComponents(string: value),
                  components.scheme?.lowercased() == "https",
                  let host = components.host, !host.isEmpty,
                  components.user == nil, components.password == nil
            else { return nil }
            components.scheme = "https"
            components.host = host.lowercased()
            components.path = ""
            components.query = nil
            components.fragment = nil
            guard let root = components.url, seen.insert(root.absoluteString).inserted else { return nil }
            return root
        }
        // The first configured server is the primary; do not mirror to it again.
        self.servers = Array(roots.dropFirst())
        let suffix = source.pathExtension
        let filename = suffix.isEmpty ? self.hash : "\(self.hash).\(suffix)"
        self.fallbackURLs = servers.map { $0.appendingPathComponent(filename).absoluteString }
            .filter { $0 != sourceURL }
    }
}

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

    private func needsVisualMetadata(contentType: String) -> Bool {
        (contentType.hasPrefix("image/") || contentType.hasPrefix("video/")) && (dim == nil || blurhash == nil)
    }

    /// Fill local preview metadata without calculating a missing server hash.
    func completing(fromLocalData data: Data, contentType: String) async throws -> Self {
        try Task.checkCancellation()
        guard needsVisualMetadata(contentType: contentType) else { return self }
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            return await fillingMissingVisualFields(from: data, contentType: contentType)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// `/media` can resize the original. Download only when the server omitted
    /// its output dimensions; this never computes a hash or a remote BlurHash.
    static func processedDimensions(
        from url: URL,
        contentType: String,
        download: @escaping @Sendable (URLRequest) async throws -> (URL, URLResponse)
    ) async throws -> String {
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            let (file, response) = try await download(request)
            defer { try? FileManager.default.removeItem(at: file) }
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw URLError(.badServerResponse)
            }
            try Task.checkCancellation()
            if let source = CGImageSourceCreateWithURL(file as CFURL, nil), let dim = dimensions(of: source) {
                return dim
            }
            if contentType.hasPrefix("video/"),
               let size = await getVideoDimensions(asset: AVURLAsset(url: file)), size.width > 0, size.height > 0 {
                return "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
            }
            throw URLError(.cannotDecodeContentData)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func dimensions(of source: CGImageSource) -> String? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0, height.intValue > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation)
            ? "\(height.intValue)x\(width.intValue)" : "\(width.intValue)x\(height.intValue)"
    }

    private func fillingMissingVisualFields(from data: Data, contentType: String) async -> Self {
        var result = self
        if let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 {
            if result.dim == nil {
                result.dim = Self.dimensions(of: source)
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
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            defer { try? FileManager.default.removeItem(at: file) }
            guard (try? data.write(to: file)) != nil else { return result }
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
                    guard let image = try? await generator.image(at: .zero).image else { return result }
                    thumbnail = image
                }
                else {
                    guard let image = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return result }
                    thumbnail = image
                }
                result.blurhash = UIImage(cgImage: thumbnail).blurHash(numberOfComponents: (4, 3))
            }
        }
        return result
    }
}

/// Accept optional server hashes and preview metadata.
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
    trace: PostMediaUploadTrace? = nil,
    download: @escaping @Sendable (URLRequest) async throws -> (URL, URLResponse) = { try await URLSession.shared.download(for: $0) }
) async throws {
    guard let url = URL(string: response.downloadURL), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
        throw URLError(.badURL)
    }
    var metadata = response.metadata
    metadata.blurhash = metadata.blurhash ?? item.blurhash
    let localType = item.contentType ?? response.type ?? "application/octet-stream"
    let serverType = response.type ?? ""
    let servedType = ["image/", "video/", "audio/"].contains(where: { serverType.hasPrefix($0) }) ? serverType : localType
    let isVisual = localType.hasPrefix("image/") || localType.hasPrefix("video/")
        || servedType.hasPrefix("image/") || servedType.hasPrefix("video/")
    if item.verb == .media && metadata.dim == nil && isVisual {
        item.state = .processing(percentage: nil)
        trace?.record("/media response omitted dimensions; output download started")
        metadata.dim = try await BlossomPostMetadata.processedDimensions(from: url, contentType: servedType, download: download)
        trace?.record("output download and dimension reading finished")
    }
    else if item.verb != .media {
        metadata.dim = metadata.dim ?? item.dim
    }
    let completed = try await metadata.completing(
        fromLocalData: item.mediaData, contentType: localType
    )
    trace?.record("local preview metadata finished")
    try Task.checkCancellation()
    item.sha256processed = completed.hash
    item.dim = completed.dim
    item.blurhash = completed.blurhash
    item.downloadUrl = response.downloadURL
    item.state = .success(response.downloadURL)
    trace?.record("photo ready to publish")
}

/// Finish the upload using server metadata and optional local preview metadata.
func uploadBlossomPostPublisher(for item: BlossomUploadItem, server: URL) -> AnyPublisher<BlossomUploadItem, Error> {
    Deferred {
        let trace = PostMediaUploadTrace()
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
                    let progressDelegate = PostMediaUploadProgressDelegate(item: item, trace: trace)
                    let session = URLSession(configuration: .default)
                    defer { session.finishTasksAndInvalidate() }
                    trace.record("Blossom /\(item.verb == .media ? "media" : "upload") request started")
                    let (data, response) = try await session.upload(for: request, from: item.mediaData, delegate: progressDelegate)
                    guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    trace.record("HTTP response \(response.statusCode) received")
                    switch response.statusCode {
                    case 200, 201, 202: break
                    case 401, 403: throw URLError(.userAuthenticationRequired)
                    default: throw URLError(.badServerResponse)
                    }
                    let result = try JSONDecoder().decode(BlossomPostUploadResponse.self, from: data)
                    trace.record("reply decoded: dimensions=\(result.metadata.dim != nil), sha256=\(result.metadata.hash != nil), blurhash=\(result.metadata.blurhash != nil)")
                    try await completeBlossomPostUpload(item, response: result, trace: trace)
                    promise(.success(item))
                }
                catch {
                    trace.record("failed, code \((error as NSError).code)")
                    item.state = .error(message: error.localizedDescription)
                    promise(.failure(error))
                }
            }
        }
        return future.handleEvents(receiveCancel: { task?.cancel() }).eraseToAnyPublisher()
    }
    .eraseToAnyPublisher()
}
