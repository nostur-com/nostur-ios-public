import Combine
import Foundation
import Network
import NostrEssentials
import XCTest
@testable import Nostur

@MainActor
final class BlossomPostUploadProgressTests: XCTestCase {
    func testUploadReportsIntermediateProgressBeforeServerFinishes() async throws {
        try await verifyIntermediateProgress(useNip96: false)
    }

    func testNip96UploadReportsIntermediateProgressBeforeServerFinishes() async throws {
        try await verifyIntermediateProgress(useNip96: true)
    }

    func testUploadEndpointMissingMetadataDoesNotBlockCompletedUpload() async throws {
        try await verifyIntermediateProgress(useNip96: false, omitMetadata: true)
    }

    private func verifyIntermediateProgress(useNip96: Bool, omitMetadata: Bool = false) async throws {
        let body = Data(repeating: 42, count: 8 * 1024 * 1024)
        let item = BlossomUploadItem(data: body, contentType: "image/jpeg", authorizationHeader: "test-auth", verb: omitMetadata ? .upload : nil)
        let bag = useNip96 ? MediaRequestBag(apiUrl: URL(string: "http://127.0.0.1")!, mediaData: body, authorizationHeader: "test-auth", boundary: "test-boundary") : nil
        let server = try SlowPhotoUploadServer(bodySize: bag?.httpBody.count ?? body.count, omitMetadata: omitMetadata)
        let ready = expectation(description: "Local upload server ready")
        server.start { ready.fulfill() }
        defer { server.stop() }
        await fulfillment(of: [ready], timeout: 5)
        let port = try XCTUnwrap(server.listener.port)
        let serverURL = URL(string: "http://127.0.0.1:\(port.rawValue)")!
        bag?.apiUrl = serverURL.appendingPathComponent("upload")
        let intermediate = expectation(description: "Progress between 0 and 100")
        let responseWait = expectation(description: "Transfer complete before the HTTP response")
        let completed = expectation(description: "Upload completed")
        var sawIntermediate = false
        var sawResponseWait = false
        let states = bag.map { $0.$state.eraseToAnyPublisher() } ?? item.$state.eraseToAnyPublisher()
        let observation = states.sink { state in
            if case .uploading(let percentage) = state, let percentage, (1..<100).contains(percentage), !sawIntermediate {
                sawIntermediate = true
                intermediate.fulfill()
            }
            if case .uploading(percentage: 100) = state, !sawResponseWait {
                sawResponseWait = true
                XCTAssertNil(bag?.downloadUrl ?? item.downloadUrl)
                responseWait.fulfill()
            }
        }
        let publisher = bag.map { uploadNip96PostPublisher(for: $0).map(\.downloadUrl).eraseToAnyPublisher() }
            ?? uploadBlossomPostPublisher(for: item, server: serverURL).map(\.downloadUrl).eraseToAnyPublisher()
        let upload = publisher
            .sink(receiveCompletion: { result in
                if case .failure(let error) = result { XCTFail("Upload failed: \(error)") }
                completed.fulfill()
            }, receiveValue: { result in
                XCTAssertEqual(result, "https://media.example/photo.jpg")
            })
        await fulfillment(of: [intermediate, responseWait, completed], timeout: 15)
        withExtendedLifetime((observation, upload)) {}
        XCTAssertTrue(bag?.finished ?? item.finished)
        if omitMetadata {
            XCTAssertNil(item.sha256processed)
        }
    }

    func testSmallUploadWaitsForResponseAfterOnlyProgressCallback() async {
        let item = BlossomUploadItem(data: Data(repeating: 42, count: 100), authorizationHeader: "")
        item.state = .uploading(percentage: 0)
        let delegate = PostMediaUploadProgressDelegate(item: item)
        let responseWait = expectation(description: "Single-chunk upload waits for server response")
        let observation = item.$state.sink { state in
            if case .uploading(percentage: 100) = state { responseWait.fulfill() }
            if case .processing = state { XCTFail("Body completion must not claim server processing") }
        }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://example.com/upload")!)
        delegate.urlSession(session, task: task, didSendBodyData: 100, totalBytesSent: 100, totalBytesExpectedToSend: 100)
        await fulfillment(of: [responseWait], timeout: 2)
        withExtendedLifetime(observation) {}
        XCTAssertFalse(item.finished)
        XCTAssertTrue(ComposerMediaUploadState.waitingForServer.isActive)
        XCTAssertTrue(ComposerMediaUploadState.readingDimensions.isActive)
    }

    func testAlmostCompleteBodyDoesNotClaimAllBytesWereSent() async {
        let item = BlossomUploadItem(data: Data(repeating: 42, count: 1000), authorizationHeader: "")
        item.state = .uploading(percentage: 0)
        let delegate = PostMediaUploadProgressDelegate(item: item)
        let progress = expectation(description: "Last incomplete chunk stays below 100 percent")
        let observation = item.$state.sink { state in
            if case .uploading(percentage: 99) = state { progress.fulfill() }
            if case .uploading(percentage: 100) = state { XCTFail("One byte still needs sending") }
        }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://example.com/upload")!)
        delegate.urlSession(session, task: task, didSendBodyData: 999, totalBytesSent: 999, totalBytesExpectedToSend: 1000)
        await fulfillment(of: [progress], timeout: 2)
        withExtendedLifetime(observation) {}
    }

    func testLateProgressCannotOverwriteProcessedResult() async {
        let item = BlossomUploadItem(data: Data(), authorizationHeader: "")
        let delegate = PostMediaUploadProgressDelegate(item: item)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://example.com/upload")!)
        item.state = .success("https://media.example/photo.jpg")
        let unexpectedProgress = expectation(description: "Completed upload must stay completed")
        unexpectedProgress.isInverted = true
        let observation = item.$state.sink { state in
            if case .uploading = state { unexpectedProgress.fulfill() }
        }
        delegate.urlSession(session, task: task, didSendBodyData: 50, totalBytesSent: 50, totalBytesExpectedToSend: 100)
        await fulfillment(of: [unexpectedProgress], timeout: 0.1)
        withExtendedLifetime(observation) {}
        XCTAssertTrue(item.finished)
    }
}

/// Read a real HTTP upload slowly enough to observe byte progress. All mutable
/// server state belongs to this queue; no importer or managed objects are used.
private final class SlowPhotoUploadServer: @unchecked Sendable {
    let listener: NWListener
    private let queue = DispatchQueue(label: "com.nostur.tests.photo-upload")
    private let bodySize: Int
    private let omitMetadata: Bool
    private var connection: NWConnection?
    private var header = Data()
    private var receivedBodyBytes: Int?

    init(bodySize: Int, omitMetadata: Bool = false) throws {
        self.bodySize = bodySize
        self.omitMetadata = omitMetadata
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start(onReady: @escaping @Sendable () -> Void) {
        listener.stateUpdateHandler = { state in
            if case .ready = state { onReady() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.connection = connection
            connection.start(queue: self.queue)
            self.receive()
        }
        listener.start(queue: queue)
    }

    func stop() {
        queue.async {
            self.connection?.cancel()
            self.listener.cancel()
        }
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self, error == nil, let data, !data.isEmpty else { return }
            if let count = self.receivedBodyBytes {
                self.receivedBodyBytes = count + data.count
            }
            else {
                self.header.append(data)
                if let end = self.header.range(of: Data("\r\n\r\n".utf8)) {
                    self.receivedBodyBytes = self.header.count - end.upperBound
                    self.header = Data()
                }
            }
            if (self.receivedBodyBytes ?? 0) >= self.bodySize {
                self.queue.asyncAfter(deadline: .now() + 0.2) { self.respond() }
            }
            else if !complete {
                self.queue.asyncAfter(deadline: .now() + 0.002) { self.receive() }
            }
        }
    }

    private func respond() {
        let json = omitMetadata
            ? #"{"url":"https://media.example/photo.jpg","type":"image/jpeg"}"#
            : #"{"url":"https://media.example/photo.jpg","sha256":"server-hash","type":"image/jpeg","nip94":[["dim","32x32"],["blurhash","server-blurhash"]],"status":"success","nip94_event":{"tags":[["url","https://media.example/photo.jpg"],["ox","original-hash"]]}}"#
        let response = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(json.utf8.count)\r\nConnection: close\r\n\r\n\(json)".utf8)
        connection?.send(content: response, completion: .contentProcessed { [weak self] _ in self?.connection?.cancel() })
    }
}
