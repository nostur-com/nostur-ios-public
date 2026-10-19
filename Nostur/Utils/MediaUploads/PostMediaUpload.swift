import Combine
import Foundation
import NostrEssentials

/// Deliver byte progress during scrolling, including a small upload's only
/// callback. Once all bytes are sent, keep the server-processing wait distinct.
@MainActor
final class PostMediaUploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let update: (Int) -> Void

    init(item: BlossomUploadItem) {
        update = { [weak item] percentage in
            guard let item, let state = Self.nextState(item.state, percentage: percentage) else { return }
            item.state = state
        }
    }

    init(bag: MediaRequestBag) {
        update = { [weak bag] percentage in
            guard let bag, let state = Self.nextState(bag.state, percentage: percentage) else { return }
            bag.state = state
        }
    }

    private static func nextState(_ state: UploadState, percentage: Int) -> UploadState? {
        guard case .uploading(let current) = state else { return nil }
        let next = max(current ?? 0, percentage)
        guard current != next else { return nil }
        return next == 100 ? .processing(percentage: nil) : .uploading(percentage: next)
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0, totalBytesSent > 0 else { return }
        let percentage = min(100, Int(ceil(Double(totalBytesSent) / Double(totalBytesExpectedToSend) * 100)))
        Task { @MainActor in self.update(percentage) }
    }
}

/// Preserve the existing NIP-96 response/polling flow while using a native upload
/// task with explicit progress, just like Blossom photo posts.
func uploadNip96PostPublisher(for bag: MediaRequestBag) -> AnyPublisher<MediaRequestBag, Error> {
    Deferred {
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
                    let progressDelegate = PostMediaUploadProgressDelegate(bag: bag)
                    let session = URLSession(configuration: .default)
                    defer { session.finishTasksAndInvalidate() }
                    let (data, response) = try await session.upload(for: request, from: bag.httpBody, delegate: progressDelegate)
                    guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    switch response.statusCode {
                    case 200, 201, 202: break
                    case 401: throw URLError(.userAuthenticationRequired)
                    default: throw URLError(.badServerResponse)
                    }
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    bag.uploadResponse = try decoder.decode(UploadResponse.self, from: data)
                    promise(.success(bag))
                }
                catch {
                    bag.state = .error(message: error.localizedDescription)
                    promise(.failure(error))
                }
            }
        }
        return future.handleEvents(receiveCancel: { task?.cancel() }).eraseToAnyPublisher()
    }
    .eraseToAnyPublisher()
}
