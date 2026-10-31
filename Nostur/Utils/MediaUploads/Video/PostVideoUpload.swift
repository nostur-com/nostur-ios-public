import AVFoundation
import Foundation
import NostrEssentials
import UIKit

struct PreparedPostVideoMedia: Sendable {
    let key: String
    let fileURL: URL
    let contentType: String
    let hash: String
    let dim: String?
    let blurhash: String?
    let videoID: UUID?
}

enum PostVideoUploadError: LocalizedError {
    case tooLarge, unauthorized, rejected(Int), invalidResponse, signing, preparation

    var errorDescription: String? {
        switch self {
        case .tooLarge: return String(localized: "The server's upload size limit was exceeded. Retry with a smaller video or choose another server.")
        case .unauthorized: return String(localized: "The media server did not authorize this upload. Check your server settings and try again.")
        case .rejected(let status): return String(localized: "The media server rejected the upload (HTTP \(status)). Your attachments have been kept.")
        case .invalidResponse: return String(localized: "The media server did not return a usable file. Please try again.")
        case .signing: return String(localized: "Could not authorize the media upload. Please try again.")
        case .preparation: return String(localized: "Could not prepare every attachment. Nothing has been posted. Please try again.")
        }
    }

    static func check(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw Self.invalidResponse }
        switch response.statusCode {
        case 200...299: break
        case 413: throw Self.tooLarge
        case 401, 403: throw Self.unauthorized
        default: throw Self.rejected(response.statusCode)
        }
    }
}

/// Write multipart bodies incrementally, using only generic filenames. The exact
/// file hashed for NIP-98 authorization is the file supplied to URLSession.
enum VideoMultipartBody {
    static func make(file: URL, contentType: String, boundary: String) throws -> URL {
        let url = TemporaryMediaFiles.shared.makeURL(extension: "multipart")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: url) } }
        let output = try FileHandle(forWritingTo: url)
        defer { try? output.close() }
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        let ext = contentType == "video/mp4" ? "mp4" : (contentType == "image/gif" ? "gif" : "jpg")
        try output.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"mediafile\"; filename=\"media.\(ext)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8))
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            try output.write(contentsOf: chunk)
        }
        try output.write(contentsOf: Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"uploadtype\"\r\n\r\nmedia\r\n--\(boundary)--\r\n".utf8))
        completed = true
        return url
    }
}

private struct VideoNip96Response: Decodable {
    let status: String
    let processingUrl: String?
    let percentage: Int?
    let nip94Event: Nip94Event?
}

@MainActor
extension NewPostModel {
    func cancelVideoPostUpload() {
        videoPostAttemptID = UUID()
        videoPostTask?.cancel()
        videoPostTask = nil
        for video in typingTextModel.pastedVideos where video.uploadState.isActive {
            video.uploadState = .idle
        }
        typingTextModel.uploading = false
        typingTextModel.sending = false
    }

    func uploadPostWithVideos(pubkey: String, account: CloudAccount, method: UploadMethod,
                              server: URL, replyTo: ReplyTo?, quotePost: QuotePost?, onDismiss: @escaping () -> Void) {
        videoPostTask?.cancel()
        let attempt = UUID()
        videoPostAttemptID = attempt
        uploadError = nil
        guard typingTextModel.voiceRecording == nil else {
            failImageUpload(String(localized: "Finish or remove the voice recording before posting a video."))
            return
        }
        let videos = typingTextModel.pastedVideos
        let images = typingTextModel.pastedImages
        let isShort = nEvent?.kind == .shortVideos
        // Bind reusable upload receipts to account, destination, privacy and content.
        let destination = pubkey + "|" + server.absoluteString + "|"
        videoPostTask = Task { [weak self] in
            guard let self else { return }
            var transientFiles: [URL] = []
            defer { for url in transientFiles { try? FileManager.default.removeItem(at: url) } }
            do {
                var media: [PreparedPostVideoMedia] = []
                // Retain the existing photo conversion; never publish a partial result.
                let photoItems = await prepareUploadItems(pubkey: pubkey, images: images,
                                                          typingTextModel: typingTextModel, uploadMethod: .blossom)
                guard photoItems.count == images.count else { throw PostVideoUploadError.preparation }
                for (offset, item) in photoItems.enumerated() {
                    let file = TemporaryMediaFiles.shared.makeURL(extension: "image")
                    transientFiles.append(file)
                    let data = item.0
                    let hash = try await videoFileWork { () throws -> String in
                        try data.write(to: file)
                        return try VideoPreparation.hashFile(file)
                    }
                    media.append(PreparedPostVideoMedia(key: "photo|" + images[offset].uniqueId,
                        fileURL: file, contentType: item.1, hash: hash, dim: nil, blurhash: item.2, videoID: nil))
                }
                for video in videos {
                    try Task.checkCancellation()
                    video.uploadState = .preparing
                    video.preparationProgress = 0
                    let quality = video.quality
                    let prepared: PreparedVideo
                    if let cached = video.preparedVideo, cached.quality == quality,
                       cached.shortVideo == isShort, FileManager.default.fileExists(atPath: cached.url.path) {
                        prepared = cached
                    } else {
                        let input = video.videoURL
                        prepared = try await videoFileWork {
                            try await VideoPreparation.prepare(inputURL: input, quality: quality, shortVideo: isShort) { fraction in
                                Task { @MainActor [weak self, weak video] in
                                    guard self?.videoPostAttemptID == attempt else { return }
                                    video?.preparationProgress = fraction
                                }
                            }
                        }
                        guard videoPostAttemptID == attempt else {
                            try? FileManager.default.removeItem(at: prepared.url)
                            throw CancellationError()
                        }
                        if let old = video.preparedVideo, old.url != video.videoURL { try? FileManager.default.removeItem(at: old.url) }
                        video.preparedVideo = prepared
                    }
                    // Revalidate the cached file before it crosses the upload boundary.
                    try await videoFileWork { try await VideoPreparation.verifyPrivacy(of: prepared.url) }
                    guard videoPostAttemptID == attempt else { throw CancellationError() }
                    typingTextModel.vineVideoDim = "\(Int(prepared.dimensions.width))x\(Int(prepared.dimensions.height))"
                    let key = "video|\(video.id)|\(quality.rawValue)"
                    media.append(PreparedPostVideoMedia(key: key, fileURL: prepared.url, contentType: "video/mp4",
                        hash: prepared.sha256, dim: typingTextModel.vineVideoDim, blurhash: nil, videoID: video.id))
                    if isShort {
                        let frame = await getVideoFirstFrame(asset: AVURLAsset(url: prepared.url))
                        guard let frame, let jpeg = frame.jpegData(compressionQuality: 0.85) else { throw PostVideoUploadError.preparation }
                        let file = TemporaryMediaFiles.shared.makeURL(extension: "jpg")
                        transientFiles.append(file)
                        let hash = try await videoFileWork { () throws -> String in
                            try jpeg.write(to: file)
                            return try VideoPreparation.hashFile(file)
                        }
                        media.append(PreparedPostVideoMedia(key: key + "|thumbnail", fileURL: file, contentType: "image/jpeg",
                            hash: hash, dim: nil, blurhash: frame.resized(to: CGSize(width: 32, height: 32)).blurHash(numberOfComponents: (4, 3)), videoID: nil))
                    }
                }
                var imetas: [Imeta] = []
                for item in media {
                    try Task.checkCancellation()
                    guard videoPostAttemptID == attempt else { throw CancellationError() }
                    let receiptKey = destination + item.key + "|" + item.hash
                    if let receipt = completedVideoPostUploads[receiptKey] {
                        imetas.append(receipt)
                        continue
                    }
                    let video = videos.first { $0.id == item.videoID }
                    video?.uploadState = .uploading(percentage: 0)
                    let bodyURL: URL
                    let event: NEvent
                    var request: URLRequest
                    switch method {
                    case .blossom:
                        bodyURL = item.fileURL
                        event = getUnsignedAuthorizationHeaderEvent(pubkey: pubkey, sha256hex: item.hash)
                        request = URLRequest(url: server.appendingPathComponent("upload"))
                        request.httpMethod = "PUT"
                        request.setValue(item.contentType, forHTTPHeaderField: "Content-Type")
                        request.setValue(item.hash, forHTTPHeaderField: "X-SHA-256")
                    case .nip96:
                        let boundary = UUID().uuidString
                        bodyURL = try await videoFileWork { try VideoMultipartBody.make(file: item.fileURL, contentType: item.contentType, boundary: boundary) }
                        transientFiles.append(bodyURL)
                        let hash = try await videoFileWork { try VideoPreparation.hashFile(bodyURL) }
                        event = getUnsignedAuthorizationHeaderEvent96(pubkey: pubkey, sha256hex: hash, method: "POST", apiUrl: server)
                        request = URLRequest(url: server)
                        request.httpMethod = "POST"
                        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                    }
                    let signed = try await signVideoUpload(event, account: account)
                    try Task.checkCancellation()
                    guard let auth = toHttpAuthHeader(signed) else { throw PostVideoUploadError.signing }
                    request.setValue(auth, forHTTPHeaderField: "Authorization")
                    let byteCount = try bodyURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    request.setValue(String(byteCount), forHTTPHeaderField: "Content-Length")
                    request.timeoutInterval = 120
                    let delegate = VideoFileUploadProgress { [weak self, weak video] percent in
                        guard self?.videoPostAttemptID == attempt else { return }
                        video?.uploadState = percent == 100 ? .waitingForServer : .uploading(percentage: percent)
                    }
                    let session = URLSession(configuration: .default)
                    defer { session.invalidateAndCancel() }
                    let data = try await PostVideoFileTransfer.upload(request: request, file: bodyURL, session: session, delegate: delegate)
                    let imeta: Imeta
                    switch method {
                    case .blossom:
                        let result = try JSONDecoder().decode(BlossomPostUploadResponse.self, from: data)
                        guard let url = URL(string: result.downloadURL), url.host != nil, ["https", "http"].contains(url.scheme) else { throw PostVideoUploadError.invalidResponse }
                        let hash = result.metadata.hash
                        let plan = BlossomPostMirrorPlan(sourceURL: result.downloadURL, hash: hash, serverStrings: SettingsStore.shared.blossomServerList)
                        imeta = Imeta(url: result.downloadURL, dim: result.metadata.dim ?? item.dim, hash: hash,
                                      blurhash: result.metadata.blurhash ?? item.blurhash, fallbackURLs: plan?.fallbackURLs ?? [])
                    case .nip96:
                        imeta = try await finishVideoNip96(data: data, session: session, baseURL: server, fallback: item) { state in
                            guard self.videoPostAttemptID == attempt else { return }
                            video?.uploadState = state
                        }
                    }
                    try Task.checkCancellation()
                    guard videoPostAttemptID == attempt else { throw CancellationError() }
                    completedVideoPostUploads[receiptKey] = imeta
                    imetas.append(imeta)
                }
                guard videoPostAttemptID == attempt, typingTextModel.pastedVideos.map(\.id) == videos.map(\.id),
                      typingTextModel.pastedImages.map(\.uniqueId) == images.map(\.uniqueId),
                      activeAccount?.publicKey == pubkey, !isReplyInPrivate else { throw CancellationError() }
                videoPostAttemptID = UUID() // Ignore any final, queued progress callbacks.
                videoPostTask = nil
                for video in videos { video.uploadState = .uploaded }
                typingTextModel.uploading = false
                typingTextModel.sending = false
                _sendNow(imetas: imetas, replyTo: replyTo, quotePost: quotePost, onDismiss: onDismiss)
                if case .blossom = method {
                    let mirrors = imetas.map { imeta in
                        let mirror = BlossomUploadItem(data: Data(), authorizationHeader: "")
                        mirror.downloadUrl = imeta.url
                        mirror.sha256processed = imeta.hash
                        return mirror
                    }
                    mirrorBlossomUploads(mirrors, account: account, serverStrings: SettingsStore.shared.blossomServerList)
                }
            } catch {
                guard videoPostAttemptID == attempt else { return }
                let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                for video in videos {
                    video.uploadState = cancelled ? .idle : .failed(error.localizedDescription)
                }
                typingTextModel.uploading = false
                typingTextModel.sending = false
                if !cancelled { uploadError = error.localizedDescription }
            }
            if videoPostAttemptID == attempt { videoPostTask = nil }
        }
    }
}

/// Detached file processing never reads a managed object or mutable composer state.
func videoFileWork<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    let worker = Task.detached(priority: .userInitiated, operation: operation)
    let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation()
    return result
}

@MainActor
func finishVideoNip96(data: Data, session: URLSession, baseURL: URL, fallback: PreparedPostVideoMedia,
                             update: (ComposerMediaUploadState) -> Void) async throws -> Imeta {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    var result = try decoder.decode(VideoNip96Response.self, from: data)
    let deadline = Date().addingTimeInterval(120)
    var processingURL = result.processingUrl.flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
    while result.status == "processing" {
        try Task.checkCancellation()
        guard Date() < deadline,
              let url = processingURL, url.host != nil,
              ["https", "http"].contains(url.scheme) else { throw PostVideoUploadError.invalidResponse }
        update(.processing(percentage: result.percentage))
        try await Task.sleep(nanoseconds: 2_500_000_000)
        let (data, response) = try await session.data(from: url)
        try PostVideoUploadError.check(response)
        result = try decoder.decode(VideoNip96Response.self, from: data)
        if let nextURL = result.processingUrl {
            processingURL = URL(string: nextURL, relativeTo: baseURL)?.absoluteURL
        }
    }
    guard ["success", "completed"].contains(result.status), let tags = result.nip94Event?.tags,
          let url = tags.first(where: { $0.type == "url" })?.value,
          let parsedURL = URL(string: url), parsedURL.host != nil, ["https", "http"].contains(parsedURL.scheme) else { throw PostVideoUploadError.invalidResponse }
    return Imeta(url: url, dim: tags.first(where: { $0.type == "dim" })?.value ?? fallback.dim,
                 hash: tags.first(where: { $0.type == "x" })?.value,
                 blurhash: tags.first(where: { $0.type == "blurhash" })?.value ?? fallback.blurhash)
}

@MainActor
final class VideoFileUploadProgress: NSObject, URLSessionTaskDelegate {
    private let update: (Int) -> Void
    init(update: @escaping (Int) -> Void) { self.update = update }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData: Int64,
                               totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        let percent = totalBytesSent >= totalBytesExpectedToSend ? 100 : min(99, Int(Double(totalBytesSent) / Double(totalBytesExpectedToSend) * 100))
        Task { @MainActor in update(percent) }
    }
}

/// Cancellation and signer callbacks can arrive on different queues. Only the
/// continuation/result bookkeeping is locked; callbacks run outside the lock.
private final class VideoUploadSignatureWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NEvent, Error>?
    private var result: Result<NEvent, Error>?

    func install(_ continuation: CheckedContinuation<NEvent, Error>) {
        lock.lock()
        let result = result
        if result == nil { self.continuation = continuation }
        lock.unlock()
        if let result { continuation.resume(with: result) }
    }

    func resolve(_ value: Result<NEvent, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: value)
    }
}

@MainActor
private func signVideoUpload(_ event: NEvent, account: CloudAccount) async throws -> NEvent {
    let waiter = VideoUploadSignatureWaiter()
    let timeout = Task {
        do {
            try await Task.sleep(nanoseconds: 60_000_000_000)
            waiter.resolve(.failure(PostVideoUploadError.signing))
        } catch { }
    }
    defer { timeout.cancel() }
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            waiter.install(continuation)
            batchSignEvents([event], account: account) { events in
                if let signed = events[event.id] { waiter.resolve(.success(signed)) }
                else { waiter.resolve(.failure(PostVideoUploadError.signing)) }
            }
        }
    } onCancel: { waiter.resolve(.failure(CancellationError())) }
}

/// Private replies still need Data for encryption, but share the same verified
/// preparation cache. Never substitute the unprocessed original on failure.
@MainActor
func prepareComposerVideoData(_ video: PostedVideoMeta, shortVideo: Bool) async -> (URL, Data)? {
    do {
        video.uploadState = .preparing
        let prepared: PreparedVideo
        if let cached = video.preparedVideo, cached.quality == video.quality,
           cached.shortVideo == shortVideo, FileManager.default.fileExists(atPath: cached.url.path) {
            prepared = cached
        } else {
            let input = video.videoURL
            let quality = video.quality
            prepared = try await videoFileWork {
                try await VideoPreparation.prepare(inputURL: input, quality: quality, shortVideo: shortVideo)
            }
            video.preparedVideo = prepared
        }
        let data = try await videoFileWork {
            try await VideoPreparation.verifyPrivacy(of: prepared.url)
            return try Data(contentsOf: prepared.url)
        }
        return (prepared.url, data)
    } catch {
        if !Task.isCancelled { video.uploadState = .failed(error.localizedDescription) }
        return nil
    }
}

@MainActor
func uploadEncryptedPostVideoFile(data: Data, authHeader: String, server: URL,
                                  progress: @escaping (Int) -> Void) async throws -> String {
    let url = TemporaryMediaFiles.shared.makeURL(extension: "encrypted")
    defer { try? FileManager.default.removeItem(at: url) }
    try await videoFileWork { try data.write(to: url) }
    var request = URLRequest(url: server.appendingPathComponent("upload"))
    request.httpMethod = "PUT"
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    let session = URLSession(configuration: .default)
    defer { session.invalidateAndCancel() }
    let delegate = VideoFileUploadProgress(update: progress)
    let body = try await PostVideoFileTransfer.upload(request: request, file: url, session: session, delegate: delegate)
    let result = try JSONDecoder().decode(BlossomPostUploadResponse.self, from: body)
    guard let download = URL(string: result.downloadURL), download.host != nil, ["https", "http"].contains(download.scheme) else {
        throw PostVideoUploadError.invalidResponse
    }
    return result.downloadURL
}


/// Shared transfer for public files and encrypted private-reply files.
enum PostVideoFileTransfer {
    static func upload(request: URLRequest, file: URL, session: URLSession,
                       delegate: VideoFileUploadProgress) async throws -> Data {
        try Task.checkCancellation()
        let (body, response) = try await session.upload(for: request, fromFile: file, delegate: delegate)
        try PostVideoUploadError.check(response)
        return body
    }
}
