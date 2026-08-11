import Foundation
import Testing
@testable import Nostur

struct ShortVideoPlaybackURLTests {
    @Test func divineBareHashPrefersStreamingDerivatives() throws {
        let hash = "4283ad53519eb9e45bef88d3ae7dc5fe56a72d3fbfc016ca4210ab8e9f73ce28"
        let publishedURL = try #require(URL(string: "https://media.divine.video/\(hash)"))

        #expect(shortVideoPlaybackURLs(for: publishedURL).map(\.absoluteString) == [
            "https://media.divine.video/\(hash)/720p.mp4",
            "https://media.divine.video/\(hash)/480p.mp4",
            "https://media.divine.video/\(hash)/hls/master.m3u8",
            publishedURL.absoluteString
        ])
    }

    @Test func nonDivineURLIsUnchanged() throws {
        let publishedURL = try #require(URL(string: "https://cdn.example.com/video.mp4"))
        #expect(shortVideoPlaybackURLs(for: publishedURL) == [publishedURL])
    }

    @Test func divineDerivativeURLIsNotRewrittenAgain() throws {
        let hash = "4283ad53519eb9e45bef88d3ae7dc5fe56a72d3fbfc016ca4210ab8e9f73ce28"
        let derivativeURL = try #require(URL(string: "https://media.divine.video/\(hash)/720p.mp4"))
        #expect(shortVideoPlaybackURLs(for: derivativeURL) == [derivativeURL])
    }

    @Test func nonHashDivinePathIsUnchanged() throws {
        let publishedURL = try #require(URL(string: "https://media.divine.video/not-a-hash"))
        #expect(shortVideoPlaybackURLs(for: publishedURL) == [publishedURL])
    }
}
