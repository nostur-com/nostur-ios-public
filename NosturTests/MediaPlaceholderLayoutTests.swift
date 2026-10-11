import XCTest
import SwiftUI
import Nuke
@testable import Nostur

@available(iOS 17.0, *)
@MainActor
final class MediaPlaceholderLayoutTests: XCTestCase {
    func testIntegerPortraitMetadataKeepsRenderedHeightAfterLoading() async throws {
        try await verifyIntegerPortraitHeight(inList: false)
    }

    func testIntegerPortraitMetadataKeepsListHeightAfterLoading() async throws {
        try await verifyIntegerPortraitHeight(inList: true)
    }

    private func verifyIntegerPortraitHeight(inList: Bool) async throws {
        let url = URL(string: "https://nostr-relay.derekross.me/a51e1379aa8ecba0b4b43845271042193633158a69dfae366b6f16ee811b0f93.png")!
        let tags = [["imeta", "url \(url.absoluteString)", "x a51e1379aa8ecba0b4b43845271042193633158a69dfae366b6f16ee811b0f93", "size 266151", "m image/png", "dim 1080x2404", "blurhash [E8zH7-tEeNF?1%5NXWTR%R#s;j?5MND$,s=53Il%3s=NDRhs;oN$,s=R%WV-Ys=SdWT-Yt9NFWU", "ox a51e1379aa8ecba0b4b43845271042193633158a69dfae366b6f16ee811b0f93"]]
        let serialized = String(decoding: try JSONSerialization.data(withJSONObject: tags), as: UTF8.self)
        let item = try await bg().perform {
            let event = Event(context: bg())
            event.tagsSerialized = serialized
            defer { bg().delete(event) }
            let (_, _, items) = NRContentElementBuilder.shared.buildElements(input: url.absoluteString, fastTags: event.fastTags)
            return try XCTUnwrap(items.first)
        }
        XCTAssertEqual(item.dimensions, CGSize(width: 1080, height: 2404))

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
        XCTAssertEqual(try XCTUnwrap(probe.heights.last), 400 * 2404.0 / 1080.0, accuracy: 0.1)

        // Pixel content does not affect sizing; reproduce the supplied PNG's canvas locally.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1080, height: 2404), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1080, height: 2404))
        }
        loader.deliver(try XCTUnwrap(image.pngData()), url: url)
        await fulfillment(of: [decoded], timeout: 5)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(probe.heights.isEmpty)
        for height in probe.heights {
            XCTAssertEqual(height, 400 * 2404.0 / 1080.0, accuracy: 0.1)
        }
        print("INTEGER_PORTRAIT_MEDIA_HEIGHTS: \(probe.heights)")
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
