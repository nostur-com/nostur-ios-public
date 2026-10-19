import Combine
import Foundation
import NostrEssentials

/// Correlate upload stages without logging authorization, URLs, or photo content.
struct PostMediaUploadTrace: Sendable {
    private let id = String(UUID().uuidString.prefix(8))
    private let startedAt = ProcessInfo.processInfo.systemUptime

    func record(_ stage: String) {
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        L.og.info("Photo upload \(id, privacy: .public) +\(elapsed)s: \(stage, privacy: .public)")
    }
}

/// Deliver byte progress during scrolling, including a small upload's only
/// callback. Sending all bytes does not mean the server has replied.
@MainActor
final class PostMediaUploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let update: (Int) -> Void
    nonisolated private let trace: PostMediaUploadTrace

    init(item: BlossomUploadItem, trace: PostMediaUploadTrace = PostMediaUploadTrace()) {
        self.trace = trace
        update = { [weak item] percentage in
            guard let item, let state = Self.nextState(item.state, percentage: percentage) else { return }
            item.state = state
            if percentage == 100 { trace.record("body sent; awaiting HTTP response") }
        }
    }

    init(bag: MediaRequestBag, trace: PostMediaUploadTrace = PostMediaUploadTrace()) {
        self.trace = trace
        update = { [weak bag] percentage in
            guard let bag, let state = Self.nextState(bag.state, percentage: percentage) else { return }
            bag.state = state
            if percentage == 100 { trace.record("body sent; awaiting HTTP response") }
        }
    }

    private static func nextState(_ state: UploadState, percentage: Int) -> UploadState? {
        guard case .uploading(let current) = state else { return nil }
        let next = max(current ?? 0, percentage)
        guard current != next else { return nil }
        return .uploading(percentage: next)
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0, totalBytesSent > 0 else { return }
        let percentage = totalBytesSent >= totalBytesExpectedToSend
            ? 100 : min(99, Int(ceil(Double(totalBytesSent) / Double(totalBytesExpectedToSend) * 100)))
        Task { @MainActor in self.update(percentage) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        for transaction in metrics.transactionMetrics {
            if let sent = transaction.requestEndDate, let firstByte = transaction.responseStartDate {
                trace.record("network wait from request sent to response started: \(max(0, firstByte.timeIntervalSince(sent)))s")
            }
        }
    }
}

/// Preserve the existing NIP-96 response/polling flow while using a native upload
/// task with explicit progress, just like Blossom photo posts.
func uploadNip96PostPublisher(for bag: MediaRequestBag) -> AnyPublisher<MediaRequestBag, Error> {
    Deferred {
        let trace = PostMediaUploadTrace()
        var task: Task<Void, Never>?
        let future = Future<MediaRequestBag, Error> { promise in
            task = Task { @MainActor in
                do {
                    bag.state = .uploading(percentage: 0)
                    var request = URLRequest(url: bag.apiUrl)
                    request.httpMethod = bag.method
                    request.setValue("multipart/form-data; boundary=\(bag.boundary)", forHTTPHeaderField: "Content-Type")
                    request.setValue(bag.authorizationHeader, forHTTPHeaderField: "Authorization")
                    request.setValue(String(bag.httpBody.count), forHTTPHeaderField: "Content-Length")
                    let progressDelegate = PostMediaUploadProgressDelegate(bag: bag, trace: trace)
                    let session = URLSession(configuration: .default)
                    defer { session.finishTasksAndInvalidate() }
                    trace.record("NIP-96 upload started")
                    let (data, response) = try await session.upload(for: request, from: bag.httpBody, delegate: progressDelegate)
                    guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    trace.record("HTTP response \(response.statusCode) received")
                    switch response.statusCode {
                    case 200, 201, 202: break
                    case 401: throw URLError(.userAuthenticationRequired)
                    default: throw URLError(.badServerResponse)
                    }
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    bag.uploadResponse = try decoder.decode(UploadResponse.self, from: data)
                    trace.record("NIP-96 reply decoded; server processing=\(bag.uploadResponse?.status == "processing")")
                    promise(.success(bag))
                }
                catch {
                    trace.record("failed, code \((error as NSError).code)")
                    bag.state = .error(message: error.localizedDescription)
                    promise(.failure(error))
                }
            }
        }
        return future.handleEvents(receiveCancel: { task?.cancel() }).eraseToAnyPublisher()
    }
    .eraseToAnyPublisher()
}
