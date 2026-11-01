import Foundation
import Nuke

/// Used only by the separate BUD-10 pipeline. Ordinary image requests never enter it.
final class BlossomDataLoader: DataLoading, @unchecked Sendable {
    private let loader: any DataLoading
    private let serverList: @Sendable (String) async -> [String]

    init(loader: (any DataLoading)? = nil,
         serverList: @escaping @Sendable (String) async -> [String] = { await BlossomMediaRecovery.fetchServerList(authorPubkey: $0) }) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        let network = DataLoader(configuration: configuration)
        network.delegate = BlossomRedirectPolicy()
        self.loader = loader ?? LimitedDataLoader(underlying: network, byteLimit: ImageProcessing.CONTENT_DOWNLOAD_SIZE_LIMIT)
        self.serverList = serverList
    }

    func loadData(with request: URLRequest,
                  didReceiveData: @escaping (Data, URLResponse) -> Void,
                  completion: @escaping (Swift.Error?) -> Void) -> any Cancellable {
        let task = Task.detached(priority: .utility) { [self] in
            do {
                guard let uri = request.url.flatMap({ BlossomURI($0.absoluteString) }) else { throw URLError(.badURL) }
                guard (uri.size ?? 0) <= ImageProcessing.CONTENT_DOWNLOAD_SIZE_LIMIT else {
                    throw LimitedDataLoader.Error.responseTooLarge(limit: ImageProcessing.CONTENT_DOWNLOAD_SIZE_LIMIT)
                }
                let deadline = Date().addingTimeInterval(25)
                var attempted = Set<URL>()
                // At most four explicit hints and eight server attempts in total.
                for source in 0...uri.authors.count {
                    try Task.checkCancellation()
                    guard Date() < deadline else { throw URLError(.timedOut) }
                    let servers: [URL]
                    if source == 0 {
                        servers = uri.servers
                    } else {
                        let values = await serverList(uri.authors[source - 1])
                        try Task.checkCancellation()
                        servers = Array(values.prefix(16).compactMap(BlossomURI.serverURL).prefix(4))
                    }
                    for server in servers {
                        try Task.checkCancellation()
                        guard Date() < deadline, attempted.count < 8 else { throw URLError(.timedOut) }
                        let url = uri.url(on: server)
                        guard attempted.insert(url).inserted else { continue }
                        let download = BlossomDownload()
                        do {
                            let (data, response) = try await withTaskCancellationHandler {
                                try await download.value(loader: loader, url: url, expectedSize: uri.size)
                            } onCancel: {
                                download.cancel()
                            }
                            try Task.checkCancellation()
                            guard uri.verify(data) else { continue }
                            didReceiveData(data, response)
                            completion(nil)
                            return
                        } catch {
                            try Task.checkCancellation()
                        }
                    }
                }
                throw URLError(.resourceUnavailable)
            } catch {
                completion(error)
            }
        }
        return BlossomLoadTask(task: task)
    }
}

private final class BlossomLoadTask: Cancellable, @unchecked Sendable {
    let task: Task<Void, Never>
    init(task: Task<Void, Never>) { self.task = task }
    func cancel() { task.cancel() }
}

private final class BlossomRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Never downgrade to HTTP or forward credentials to another location.
        guard let url = request.url, let host = url.host,
              BlossomURI.serverURL("https://\(host)") != nil,
              url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

/// Bridges Nuke's bounded streaming loader without blocking any executor.
private final class BlossomDownload: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(Data, URLResponse), Swift.Error>?
    private var cancellable: (any Cancellable)?
    private var finished = false
    private var data = Data()
    private var response: URLResponse?

    func value(loader: any DataLoading, url: URL, expectedSize: Int?) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if finished {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            lock.unlock()
            let token = loader.loadData(with: URLRequest(url: url, timeoutInterval: 5)) { [self] chunk, response in
                lock.lock()
                guard !finished else { lock.unlock(); return }
                let limit = min(expectedSize ?? ImageProcessing.CONTENT_DOWNLOAD_SIZE_LIMIT, ImageProcessing.CONTENT_DOWNLOAD_SIZE_LIMIT)
                let declaredSizeMatches = expectedSize == nil || response.expectedContentLength < 0
                    || response.expectedContentLength == Int64(expectedSize!)
                guard declaredSizeMatches, response.expectedContentLength <= Int64(limit),
                      data.count <= limit - chunk.count else {
                    lock.unlock()
                    finish(.failure(URLError(.dataLengthExceedsMaximum)))
                    return
                }
                data.append(chunk)
                self.response = response
                lock.unlock()
            } completion: { [self] error in
                if let error { finish(.failure(error)) }
                else {
                    lock.lock()
                    let data = data
                    let response = response
                    lock.unlock()
                    if let response { finish(.success((data, response))) }
                    else { finish(.failure(URLError(.zeroByteResource))) }
                }
            }
            lock.lock()
            if finished {
                lock.unlock()
                token.cancel()
            } else {
                cancellable = token
                lock.unlock()
            }
        }
    }

    private func finish(_ result: Result<(Data, URLResponse), Swift.Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = continuation
        self.continuation = nil
        // The loader callbacks retain this bridge. Release its token and buffer
        // on every exit so completed downloads cannot retain their image bytes.
        let token = cancellable
        cancellable = nil
        data = Data()
        response = nil
        lock.unlock()
        token?.cancel()
        continuation?.resume(with: result)
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }
}
