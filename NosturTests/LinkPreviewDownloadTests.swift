import XCTest
@testable import Nostur

@MainActor
final class LinkPreviewDownloadTests: XCTestCase {
    func testPastedInstallerURLDoesNotStartDownload() {
        var completed = false
        fetchMetaTags(url: URL(string: "https://nostur.com/Nostur-1.31.0.dmg")!, configuration: configuration()) { result in
            XCTAssertEqual(try? result.get(), [:])
            completed = true
        }
        XCTAssertTrue(completed)
        XCTAssertEqual(PreviewURLProtocol.requestCount, 0)
    }

    func testUnknownFileURLRejectsDiskImageResponseAtHeaders() async {
        PreviewURLProtocol.mimeType = "application/x-apple-diskimage"
        let finished = expectation(description: "Binary response rejected")
        fetchMetaTags(url: URL(string: "https://example.com/download")!, configuration: configuration()) { result in
            XCTAssertEqual(try? result.get(), [:])
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
    }

    func testLargeHTMLParsesOnlyBoundedPrefixOffMainThread() async {
        PreviewURLProtocol.mimeType = "text/html"
        let first = "<html><head><title>Small preview</title></head>"
        let padding = String(repeating: " ", count: LinkPreviewResponseLoader.maximumBytes)
        PreviewURLProtocol.body = Data((first + padding + "<meta property=\"og:description\" content=\"outside limit\">").utf8)
        let finished = expectation(description: "Bounded HTML parsed")
        fetchMetaTags(url: URL(string: "https://example.com/page")!, configuration: configuration()) { result in
            XCTAssertFalse(Thread.isMainThread)
            let tags = try? result.get()
            XCTAssertEqual(tags?["fallback_title"], "Small preview")
            XCTAssertNil(tags?["description"])
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
    }

    func testYouTubeChannelReadsMetadataAfterLargeScripts() async {
        let padding = String(repeating: " ", count: 900_000)
        PreviewURLProtocol.body = Data("""
            <script>\(padding)</script>
            <meta property="og:title" content="Orange Scarf">
            <meta property="og:image" content="https://yt3.googleusercontent.com/channel-image">
            """.utf8)
        let finished = expectation(description: "Channel HTML metadata parsed")
        let url = URL(string: "https://www.youtube.com/@The_Orange_Scarf")!
        fetchMetaTags(url: url, configuration: configuration()) { result in
            let tags = try? result.get()
            XCTAssertEqual(tags?["title"], "Orange Scarf")
            XCTAssertEqual(tags?["image"], "https://yt3.googleusercontent.com/channel-image")
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
    }

    func testYouTubeVideoStillUsesOEmbed() async {
        PreviewURLProtocol.mimeType = "application/json"
        PreviewURLProtocol.body = Data(#"{"title":"Video preview"}"#.utf8)
        let finished = expectation(description: "YouTube oEmbed JSON parsed")
        let url = URL(string: "https://www.youtube.com/watch?v=QU9kRF9tHPU")!
        fetchMetaTags(url: url, configuration: configuration()) { result in
            XCTAssertEqual(try? result.get()["title"], "Video preview")
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
    }

    override func setUp() {
        PreviewURLProtocol.requestCount = 0
        PreviewURLProtocol.mimeType = "text/html"
        PreviewURLProtocol.body = Data("<title>Preview</title>".utf8)
    }

    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreviewURLProtocol.self]
        return configuration
    }
}

private final class PreviewURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestCount = 0
    static var mimeType = "text/html"
    static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestCount += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": Self.mimeType, "Content-Length": String(Self.body.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
