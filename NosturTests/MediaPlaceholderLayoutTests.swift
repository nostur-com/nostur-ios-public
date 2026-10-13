import XCTest
import SwiftUI
import Nuke
@testable import Nostur

@available(iOS 17.0, *)
@MainActor
final class MediaPlaceholderLayoutTests: XCTestCase {
    func testIntegerPortraitMetadataKeepsRenderedHeightAfterLoading() async throws {
        try await verifyMediaHeight(inList: false)
    }

    func testIntegerPortraitMetadataKeepsListHeightAfterLoading() async throws {
        try await verifyMediaHeight(inList: true)
    }

    func testMissingDimensionsKeepsPlaceholderHeightForPortrait() async throws {
        try await verifyMediaHeight(inList: false, hasMetadata: false)
    }

    func testMissingDimensionsKeepsListPlaceholderHeightForLandscape() async throws {
        try await verifyMediaHeight(inList: true, hasMetadata: false, sourceSize: CGSize(width: 2404, height: 1080))
    }

    private func verifyMediaHeight(inList: Bool, hasMetadata: Bool = true, sourceSize: CGSize = CGSize(width: 1080, height: 2404)) async throws {
        let url = URL(string: "https://nostr-relay.derekross.me/a51e1379aa8ecba0b4b43845271042193633158a69dfae366b6f16ee811b0f93.png")!
        let tags = [["imeta", "url \(url.absoluteString)", "x a51e1379aa8ecba0b4b43845271042193633158a69dfae366b6f16ee811b0f93", "size 266151", "m image/png", "dim 1080x2404", "blurhash [E8zH7-tEeNF?1%5NXWTR%R#s;j?5MND$,s=53Il%3s=NDRhs;oN$,s=R%WV-Ys=SdWT-Yt9NFWU", "ox a51e1379aa8ecba0b4b43845271042193633158a69dfae366b6f16ee811b0f93"]]
        let serialized = String(decoding: try JSONSerialization.data(withJSONObject: hasMetadata ? tags : []), as: UTF8.self)
        let item = try await bg().perform {
            let event = Event(context: bg())
            event.tagsSerialized = serialized
            defer { bg().delete(event) }
            let (_, _, items) = NRContentElementBuilder.shared.buildElements(input: url.absoluteString, fastTags: event.fastTags)
            return try XCTUnwrap(items.first)
        }
        XCTAssertEqual(item.dimensions, hasMetadata ? CGSize(width: 1080, height: 2404) : nil)
        let expectedHeight: CGFloat = hasMetadata ? 400 * 2404.0 / 1080.0 : 300

        let lowDataMode = SettingsStore.shared.lowDataMode
        SettingsStore.shared.lowDataMode = false
        defer { SettingsStore.shared.lowDataMode = lowDataMode }
        let requested = expectation(description: "Image download starts")
        let decoded = expectation(description: "Image decoded with source dimensions")
        let loader = HeldImageLoader(requested: requested)
        let originalPipeline = ImageProcessing.shared.content
        var configuration = originalPipeline.configuration
        configuration.dataLoader = loader
        configuration.imageCache = nil
        configuration.dataCache = nil
        ImageProcessing.shared.content = ImagePipeline(configuration: configuration)
        defer { ImageProcessing.shared.content = originalPipeline }

        let subscription = receiveNotification(.iMetaInfoForUrl).sink { notification in
            guard let (receivedURL, _) = notification.object as? (String, iMetaInfo), receivedURL == url.absoluteString else { return }
            decoded.fulfill()
        }
        defer { subscription.cancel() }

        let probe = MediaHeightProbe()
        let media = MediaContentView(galleryItem: item, availableWidth: 400, placeholderAspect: 4 / 3, maxHeight: 1200, autoload: true, generateIMeta: true)
                .background {
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear { probe.heights.append(geometry.size.height) }
                            .onChange(of: geometry.size) { _, size in probe.heights.append(size.height) }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
        let container = inList
            ? AnyView(List { media.listRowInsets(EdgeInsets()) }.listStyle(.plain))
            : AnyView(ScrollView { media })
        let root = container
        .environment(\.theme, Themes.default.theme)
        .environment(\.feedImageRequestTargetSize, CGSize(width: 400, height: 700))
        let host = UIHostingController(rootView: root)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 400, height: 1000)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await fulfillment(of: [requested], timeout: 5)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(try XCTUnwrap(probe.heights.last), expectedHeight, accuracy: 0.1)

        // Generate the source canvas locally so the test does not depend on the network.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: sourceSize, format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: sourceSize))
        }
        loader.deliver(try XCTUnwrap(image.pngData()), url: url)
        await fulfillment(of: [decoded], timeout: 5)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(probe.heights.isEmpty)
        for height in probe.heights {
            XCTAssertEqual(height, expectedHeight, accuracy: 0.1)
        }
        print("MEDIA_HEIGHTS (metadata: \(hasMetadata)): \(probe.heights)")
    }
}

@MainActor
private final class MediaHeightProbe {
    var heights: [CGFloat] = []
}

private final class HeldImageLoader: DataLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var callbacks: (((Data, URLResponse) -> Void), (Swift.Error?) -> Void)?
    let requested: XCTestExpectation
    init(requested: XCTestExpectation) { self.requested = requested }

    func loadData(with request: URLRequest, didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Swift.Error?) -> Void) -> any Cancellable {
        lock.lock()
        callbacks = (didReceiveData, completion)
        lock.unlock()
        requested.fulfill()
        return HeldImageCancellation()
    }

    func deliver(_ data: Data, url: URL) {
        lock.lock()
        let callbacks = callbacks
        lock.unlock()
        callbacks?.0(data, URLResponse(url: url, mimeType: "image/png", expectedContentLength: data.count, textEncodingName: nil))
        callbacks?.1(nil)
    }
}

private final class HeldImageCancellation: Cancellable, @unchecked Sendable {
    func cancel() {}
}

@MainActor
final class MediaFallbackLoadingTests: XCTestCase {
    func testFailedPrimaryTriesFallbacksInOrderWithoutBlossomHash() async throws {
        let primary = URL(string: "https://primary.example/photo.png")!
        let missing = URL(string: "https://mirror.example/missing.png")!
        let working = URL(string: "https://mirror.example/working.png?token=123")!
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let loader = FallbackImageLoader(workingURL: working, data: try XCTUnwrap(image.pngData()))
        let originalPipeline = ImageProcessing.shared.content
        var configuration = originalPipeline.configuration
        configuration.dataLoader = loader
        configuration.imageCache = nil
        configuration.dataCache = nil
        ImageProcessing.shared.content = ImagePipeline(configuration: configuration)
        defer { ImageProcessing.shared.content = originalPipeline }

        let vm = MediaViewVM()
        let lowDataMode = SettingsStore.shared.lowDataMode
        SettingsStore.shared.lowDataMode = false
        defer { SettingsStore.shared.lowDataMode = lowDataMode }
        let loaded = await vm.load(primary, fallbackURLs: [primary, missing, missing, working])
        XCTAssertTrue(loaded)
        XCTAssertEqual(loader.requestedURLs, [primary, missing, working])
    }

    func testFailedFallbackCountsAsTriedMirror() async {
        let primary = URL(string: "https://primary.example/photo.png")!
        let missing = URL(string: "https://mirror.example/missing.png")!
        let loader = FallbackImageLoader(workingURL: nil, data: Data())
        let originalPipeline = ImageProcessing.shared.content
        var configuration = originalPipeline.configuration
        configuration.dataLoader = loader
        configuration.imageCache = nil
        configuration.dataCache = nil
        ImageProcessing.shared.content = ImagePipeline(configuration: configuration)
        defer { ImageProcessing.shared.content = originalPipeline }

        let vm = MediaViewVM()
        let loaded = await vm.load(primary, forceLoad: true, fallbackURLs: [missing])
        XCTAssertFalse(loaded)
        XCTAssertEqual(vm.state, .error("Failed to load image (tried 1 more mirror)"))
    }
}

private final class FallbackImageLoader: DataLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private let workingURL: URL?
    private let data: Data

    var requestedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }

    init(workingURL: URL?, data: Data) {
        self.workingURL = workingURL
        self.data = data
    }

    func loadData(with request: URLRequest, didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Swift.Error?) -> Void) -> any Cancellable {
        guard let url = request.url else {
            completion(URLError(.badURL))
            return HeldImageCancellation()
        }
        lock.lock()
        urls.append(url)
        lock.unlock()
        if url == workingURL {
            didReceiveData(data, URLResponse(url: url, mimeType: "image/png", expectedContentLength: data.count, textEncodingName: nil))
            completion(nil)
        }
        else {
            completion(URLError(.fileDoesNotExist))
        }
        return HeldImageCancellation()
    }
}

@MainActor
final class PreviewMediaDownloadReuseTests: XCTestCase {
    func testResizedPreviewsGenerateOriginalFileMetadataWithOneDownload() async throws {
        let url = URL(string: "https://example.com/pasted-photo.png")!
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 200), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        }
        let bytes = try XCTUnwrap(image.pngData())
        let loader = FallbackImageLoader(workingURL: url, data: bytes)
        let cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = try DataCache(path: cacheDirectory)
        defer { cache.removeAll() }
        let originalPipeline = ImageProcessing.shared.content
        var configuration = originalPipeline.configuration
        configuration.dataLoader = loader
        configuration.imageCache = nil
        configuration.dataCache = cache
        configuration.dataCachePolicy = .storeOriginalData
        ImageProcessing.shared.content = ImagePipeline(configuration: configuration)
        defer { ImageProcessing.shared.content = originalPipeline }

        for target in [CGSize(width: 20, height: 40), CGSize(width: 10, height: 20)] {
            let received = expectation(description: "Preview metadata ready")
            var metadata: iMetaInfo?
            let subscription = receiveNotification(.iMetaInfoForUrl).sink { notification in
                guard let (key, value) = notification.object as? (String, iMetaInfo), key == url.absoluteString else { return }
                metadata = value
                received.fulfill()
            }
            let vm = MediaViewVM()
            let loaded = await vm.load(url, forceLoad: true, generateIMeta: true, targetSize: target)
            XCTAssertTrue(loaded)
            await fulfillment(of: [received], timeout: 5)
            subscription.cancel()
            XCTAssertEqual(metadata?.size, CGSize(width: 100, height: 200))
            XCTAssertEqual(metadata?.hash, bytes.sha256().hexEncodedString())
            XCTAssertEqual(metadata?.fileSize, bytes.count)
            XCTAssertEqual(metadata?.mimeType, "image/png")
            XCTAssertEqual(metadata?.blurHash?.count, 28)
            let tag = PreviewMediaMetadata.tag(url: url.absoluteString, metadata: try XCTUnwrap(metadata))
            XCTAssertTrue(tag.contains("x \(bytes.sha256().hexEncodedString())"))
            XCTAssertTrue(tag.contains("dim 100x200"))
        }
        XCTAssertEqual(loader.requestedURLs, [url])
    }
}
