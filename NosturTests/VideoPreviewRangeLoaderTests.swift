import Foundation
import Testing
@testable import Nostur

struct VideoPreviewRangeLoaderTests {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreviewRangeProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test func acceptsExactRange() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let data = try await VideoPreviewRangeLoader.fetch(url: URL(string: "https://preview.test/exact")!, range: 10..<14, session: session)
        #expect(data == Data([1, 2, 3, 4]))
    }

    @Test func acceptsCompleteSmallFileAtOffsetZero() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let data = try await VideoPreviewRangeLoader.fetch(url: URL(string: "https://preview.test/ignored")!, range: 0..<128, session: session)
        #expect(data == Data([1, 2, 3, 4]))
    }

    @Test func rejectsIgnoredRangesWrongOffsetsTruncationAndUnboundedBodies() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        for scenario in ["ignored", "wrong-offset", "truncated", "oversized", "oversized-length"] {
            await #expect(throws: (any Error).self) {
                try await VideoPreviewRangeLoader.fetch(url: URL(string: "https://preview.test/\(scenario)")!, range: 10..<14, session: session)
            }
        }
    }
}

private final class PreviewRangeProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let scenario = request.url!.lastPathComponent
        let headers = ["Content-Range": scenario == "wrong-offset" ? "bytes 0-3/100" : "bytes 10-13/100"]
            .merging(scenario == "oversized-length" ? ["Content-Length": "1000000"] : [:]) { _, new in new }
        let response = HTTPURLResponse(url: request.url!, statusCode: scenario == "ignored" ? 200 : 206,
                                       httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let count = scenario == "truncated" ? 2 : scenario == "oversized" ? 5 : 4
        client?.urlProtocol(self, didLoad: Data((1...count).map(UInt8.init)))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
