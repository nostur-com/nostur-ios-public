import XCTest
import CryptoKit
import Nuke
import UIKit
@testable import Nostur

final class BlossomURITests: XCTestCase {
    private let referenceHash = "d819b922fbbf3a47e606dab12a6c316b9a0445ff4aa69d749d638ce83884cf1c"

    func testExamplePreservesHintOrderAndSize() throws {
        let uri = try XCTUnwrap(BlossomURI("blossom:\(referenceHash).jpg?xs=blossom.laantungir.net&xs=cdn.satellite.earth&xs=blossom.primal.net&as=\(referenceHash)&sz=117475"))
        XCTAssertEqual(uri.hash, referenceHash)
        XCTAssertEqual(uri.size, 117475)
        XCTAssertEqual(uri.servers.map(\.host), ["blossom.laantungir.net", "cdn.satellite.earth", "blossom.primal.net"])
        XCTAssertEqual(uri.authors, [referenceHash])
        XCTAssertEqual(uri.url(on: uri.servers[0]).absoluteString, "https://blossom.laantungir.net/\(referenceHash).jpg")
    }

    func testInvalidAndUnsupportedReferencesRemainText() {
        for value in ["blossom:abc.jpg", "blossom:\(referenceHash.uppercased()).jpg", "blossom:\(referenceHash)", "blossom:\(referenceHash).mp4", "blossom:\(referenceHash).jpg?sz=0", "blossom:\(referenceHash).jpg?sz=-1", "blossom:\(referenceHash).jpg?sz=2&sz=3"] {
            XCTAssertNil(BlossomURI(value), value)
        }
    }

    func testServerHintsAreBoundedDeduplicatedHTTPSRoots() throws {
        let uri = try XCTUnwrap(BlossomURI("blossom:\(referenceHash).jpg?xs=cdn.example.com&xs=https://cdn.example.com/&xs=http://insecure.example.com&xs=https://user:pass@example.com&xs=127.0.0.1&xs=host.local&xs=example.com/path&xs=two.example.com&xs=three.example.com&xs=four.example.com&xs=five.example.com"))
        XCTAssertEqual(uri.servers.map(\.host), ["cdn.example.com", "two.example.com", "three.example.com", "four.example.com"])
    }

    func testOnlyPostAuthorDeterminesAutomaticLoading() {
        XCTAssertTrue(BlossomURI.allowsAutomaticLoad(postAuthor: "friend", accountPubkey: "me", following: ["friend"]))
        XCTAssertTrue(BlossomURI.allowsAutomaticLoad(postAuthor: "me", accountPubkey: "me", following: []))
        XCTAssertFalse(BlossomURI.allowsAutomaticLoad(postAuthor: "stranger", accountPubkey: "me", following: ["friend"]))
        XCTAssertFalse(BlossomURI.allowsAutomaticLoad(postAuthor: nil, accountPubkey: "me", following: ["friend"]))
        XCTAssertFalse(BlossomURI.allowsAutomaticLoad(postAuthor: "friend", accountPubkey: nil, following: ["friend"]))
    }

    func testParserAddsGalleryImageWithoutRewritingNormalURLs() {
        let uri = "blossom:\(referenceHash).jpg?xs=cdn.example.com&sz=117475"
        let normal = "https://example.com/photo.jpg"
        let (elements, links, gallery) = NRContentElementBuilder.shared.buildElements(input: "Hello\n\(uri)\n\(normal)", fastTags: [])
        XCTAssertEqual(gallery.map(\.url.absoluteString), [uri, normal])
        XCTAssertEqual(elements.filter { if case .image = $0 { return true }; return false }.count, 2)
        XCTAssertTrue(links.isEmpty)
    }

    func testSentencePunctuationIsNotPartOfReference() {
        let reference = "blossom:\(referenceHash).jpg?xs=cdn.example.com&sz=117475"
        let (_, _, gallery) = NRContentElementBuilder.shared.buildElements(input: "See (\(reference)).", fastTags: [])
        XCTAssertEqual(gallery.map(\.url.absoluteString), [reference])
    }

    @MainActor
    func testCacheIdentityUsesHashAcrossMirrors() {
        let first = makeImageRequest(URL(string: "blossom:\(referenceHash).jpg?xs=one.example.com")!)
        let second = makeImageRequest(URL(string: "blossom:\(referenceHash).jpg?xs=two.example.com")!)
        XCTAssertEqual(first.userInfo[.imageIdKey] as? String, second.userInfo[.imageIdKey] as? String)
        let normal = makeImageRequest(URL(string: "https://example.com/photo.jpg")!)
        XCTAssertNil(normal.userInfo[.imageIdKey])
    }

    @MainActor
    func testBlossomUsesPostContentCacheAndSettingsRemovalIsVisible() async throws {
        let content = ImageProcessing.shared.content.configuration
        let blossom = ImageProcessing.shared.blossom.configuration
        let contentCache = try XCTUnwrap(content.dataCache as? DataCache)
        let blossomCache = try XCTUnwrap(blossom.dataCache as? DataCache)
        XCTAssertTrue(contentCache === blossomCache)
        XCTAssertTrue((content.imageCache as? ImageCache) === (blossom.imageCache as? ImageCache))
        XCTAssertEqual(blossomCache.sizeLimit, ImageProcessing.CONTENT_SIZE_MB * 1_048_576)
        XCTAssertFalse(content.dataLoadingQueue === blossom.dataLoadingQueue)

        // Exercise the same cache Settings reads and clears, without deleting
        // unrelated simulator media. Pending writes/removals must be shared too.
        await Task.detached {
            let key = "blossom-cache-settings-test-" + UUID().uuidString
            let bytes = Data("verified Blossom cache entry".utf8)
            defer { contentCache.removeData(for: key) }
            blossomCache.storeData(bytes, for: key)
            XCTAssertEqual(contentCache.cachedData(for: key), bytes)
            contentCache.removeData(for: key)
            XCTAssertNil(blossomCache.cachedData(for: key))
        }.value
    }

    func testFailedHintThenAuthorDiscoveryReturnsOnlyVerifiedBytes() async throws {
        let bytes = Data("verified image bytes".utf8)
        let referenceHash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let source = BlossomStubLoader(data: bytes, failedHost: "bad.example.com")
        let loader = BlossomDataLoader(loader: source, serverList: { _ in ["https://good.example.com"] })
        let output = try await load(loader, "blossom:\(referenceHash).jpg?xs=bad.example.com&as=\(referenceHash)&sz=\(bytes.count)")
        XCTAssertEqual(output, bytes)
        XCTAssertEqual(source.hosts, ["bad.example.com", "good.example.com"])
    }

    func testSuccessfulHintDoesNotDiscoverAuthor() async throws {
        let bytes = Data("abc".utf8)
        let referenceHash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let loader = BlossomDataLoader(loader: BlossomStubLoader(data: bytes), serverList: { _ in
            XCTFail("Author discovery must wait until hints fail")
            return []
        })
        let output = try await load(loader, "blossom:\(referenceHash).jpg?xs=good.example.com&as=\(referenceHash)")
        XCTAssertEqual(output, bytes)
    }

    func testHashAndSizeMismatchNeverReachDecoder() async {
        for suffix in ["", "&sz=2"] {
            let loader = BlossomDataLoader(loader: BlossomStubLoader(data: Data("wrong bytes".utf8)))
            do {
                _ = try await load(loader, "blossom:\(referenceHash).jpg?xs=good.example.com\(suffix)")
                XCTFail("Unverified bytes must never be delivered")
            } catch { }
        }
    }

    func testCompletedDownloadReleasesCallbackAndBufferOwnership() async throws {
        let released = expectation(description: "Completed download token released")
        let bytes = Data("abc".utf8)
        let referenceHash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let loader = BlossomDataLoader(loader: BlossomRetainingLoader(data: bytes, released: released))
        let output = try await load(loader, "blossom:\(referenceHash).jpg?xs=good.example.com")
        XCTAssertEqual(output, bytes)
        await fulfillment(of: [released], timeout: 1)
    }

    func testCancellationStopsHeldDownloadPromptly() async {
        let cancelled = expectation(description: "Underlying download cancelled")
        let completed = expectation(description: "Cancelled load completes")
        let started = expectation(description: "Download started")
        // The held loader signals when the network request has actually begun.
        let held = BlossomHeldLoader(cancelled: cancelled, started: started)
        let activeLoader = BlossomDataLoader(loader: held)
        let token = activeLoader.loadData(with: URLRequest(url: URL(string: "blossom:\(referenceHash).jpg?xs=good.example.com")!), didReceiveData: { _, _ in XCTFail("Cancelled bytes") }) { error in
            XCTAssertNotNil(error)
            completed.fulfill()
        }
        await fulfillment(of: [started], timeout: 1)
        token.cancel()
        await fulfillment(of: [cancelled, completed], timeout: 1)
    }

    @MainActor
    func testSaturatedBlossomQueueDoesNotDelayOrdinaryImages() async throws {
        let started = expectation(description: "Both Blossom slots occupied")
        started.expectedFulfillmentCount = 2
        let cancelled = expectation(description: "Held downloads cancelled")
        cancelled.expectedFulfillmentCount = 2
        var blossomConfiguration = ImageProcessing.shared.blossom.configuration
        XCTAssertEqual(blossomConfiguration.dataLoadingQueue.maxConcurrentOperationCount, 2)
        XCTAssertFalse(blossomConfiguration.dataLoadingQueue === ImageProcessing.shared.content.configuration.dataLoadingQueue)
        blossomConfiguration.imageCache = nil
        blossomConfiguration.dataCache = nil
        blossomConfiguration.dataLoader = BlossomHeldLoader(cancelled: cancelled, started: started)
        let blossom = ImagePipeline(configuration: blossomConfiguration)
        let heldTasks = (0..<3).map { index in
            blossom.imageTask(with: URL(string: "blossom:\(String(repeating: String(index), count: 64)).jpg?xs=held.example.com")!)
        }
        defer { heldTasks.reversed().forEach { $0.cancel() } }
        await fulfillment(of: [started], timeout: 1)

        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        var normalConfiguration = ImageProcessing.shared.content.configuration
        normalConfiguration.imageCache = nil
        normalConfiguration.dataCache = nil
        normalConfiguration.dataLoader = BlossomStubLoader(data: try XCTUnwrap(image.pngData()))
        let normal = ImagePipeline(configuration: normalConfiguration)
        let loaded = expectation(description: "Ordinary image loads while Blossom is saturated")
        let ordinaryTask = Task {
            do {
                _ = try await normal.imageTask(with: URL(string: "https://normal.example.com/image.png")!).response
                loaded.fulfill()
            } catch { XCTFail("Ordinary image failed: \(error)") }
        }
        await fulfillment(of: [loaded], timeout: 1)
        ordinaryTask.cancel()
        heldTasks.reversed().forEach { $0.cancel() }
        await fulfillment(of: [cancelled], timeout: 1)
    }

    private func load(_ loader: BlossomDataLoader, _ uri: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let result = BlossomTestResult()
            _ = loader.loadData(with: URLRequest(url: URL(string: uri)!), didReceiveData: { data, _ in result.data = data }) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result.data) }
            }
        }
    }
}

private final class BlossomTestResult: @unchecked Sendable { var data = Data() }
private final class BlossomTestToken: Cancellable, @unchecked Sendable {
    let onCancel: () -> Void
    init(_ onCancel: @escaping () -> Void = {}) { self.onCancel = onCancel }
    func cancel() { onCancel() }
}
private final class BlossomStubLoader: DataLoading, @unchecked Sendable {
    let data: Data
    let failedHost: String?
    private(set) var hosts: [String] = []
    init(data: Data, failedHost: String? = nil) { self.data = data; self.failedHost = failedHost }
    func loadData(with request: URLRequest, didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Error?) -> Void) -> any Cancellable {
        hosts.append(request.url!.host!)
        if request.url?.host == failedHost { completion(URLError(.cannotConnectToHost)) }
        else {
            didReceiveData(data, URLResponse(url: request.url!, mimeType: "image/jpeg", expectedContentLength: data.count, textEncodingName: nil))
            completion(nil)
        }
        return BlossomTestToken()
    }
}
private final class BlossomHeldLoader: DataLoading, @unchecked Sendable {
    let cancelled: XCTestExpectation
    let started: XCTestExpectation?
    init(cancelled: XCTestExpectation, started: XCTestExpectation? = nil) { self.cancelled = cancelled; self.started = started }
    func loadData(with request: URLRequest, didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Error?) -> Void) -> any Cancellable {
        started?.fulfill()
        return BlossomTestToken { self.cancelled.fulfill(); completion(CancellationError()) }
    }
}

private final class BlossomRetainingToken: Cancellable, @unchecked Sendable {
    let completion: (Error?) -> Void
    let released: XCTestExpectation
    init(completion: @escaping (Error?) -> Void, released: XCTestExpectation) {
        self.completion = completion
        self.released = released
    }
    func cancel() { completion(CancellationError()) }
    deinit { released.fulfill() }
}
private final class BlossomRetainingLoader: DataLoading, @unchecked Sendable {
    let data: Data
    let released: XCTestExpectation
    init(data: Data, released: XCTestExpectation) { self.data = data; self.released = released }
    func loadData(with request: URLRequest, didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Error?) -> Void) -> any Cancellable {
        let token = BlossomRetainingToken(completion: completion, released: released)
        DispatchQueue.global(qos: .utility).async { [data] in
            didReceiveData(data, URLResponse(url: request.url!, mimeType: "image/jpeg", expectedContentLength: data.count, textEncodingName: nil))
            completion(nil)
        }
        return token
    }
}
