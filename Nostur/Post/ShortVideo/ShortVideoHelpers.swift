//
//  ShortVideoHelpers.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/11/2025.
//

import Foundation
import AVKit

func parseVideoIMeta(_ tag: FastTag) -> (url: String?, duration: Int?, blurhash: String?, poster: String?) {
    guard tag.0 == "imeta" else { return (url: nil, duration: nil, blurhash: nil, poster: nil) }
    
    var url: String? = nil
    var duration: Int? = nil
    var poster: String? = nil
    var blurhash: String? = nil
    
    // Iterate through optional fields (2–9)
    for field in [tag.1, tag.2, tag.3, tag.4, tag.5, tag.6, tag.7, tag.8, tag.9] {
        guard let value = field else { continue }
        let components = value.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let key = components.first else { continue }
        guard let value = components.dropFirst().first else { continue }
        
        switch key {
        case "url":
            url = String(value)
        case "image":
            poster = String(value)
        case "blurhash":
            blurhash = String(value)
        case "duration":
            duration = Int(value)
        default:
            continue
        }
    }
    
    return (url: url, duration: duration, blurhash: blurhash, poster: poster)
}

/// Returns the playback sources to try for a short video, in priority order.
///
/// Divine publishes the raw Blossom URL before its smaller streaming
/// derivatives are ready. AVPlayer also depends on byte-range requests, which
/// are not always handled correctly by the raw endpoint. Prefer Divine's
/// fast-start MP4 derivatives, then HLS, while retaining the published URL as
/// the final fallback. Other hosts are returned unchanged.
func shortVideoPlaybackURLs(for publishedURL: URL) -> [URL] {
    guard let components = URLComponents(url: publishedURL, resolvingAgainstBaseURL: false),
          components.host?.lowercased() == "media.divine.video"
    else { return [publishedURL] }

    let pathParts = components.path.split(separator: "/", omittingEmptySubsequences: true)
    guard pathParts.count == 1 else { return [publishedURL] }

    let hash = String(pathParts[0])
    let isSHA256 = hash.count == 64 && hash.unicodeScalars.allSatisfy {
        CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
    }
    guard isSHA256 else { return [publishedURL] }

    let base = "https://media.divine.video/\(hash)"
    let candidates = [
        "\(base)/720p.mp4",
        "\(base)/480p.mp4",
        "\(base)/hls/master.m3u8",
        publishedURL.absoluteString
    ]

    var seen = Set<String>()
    return candidates.compactMap { candidate in
        guard seen.insert(candidate).inserted else { return nil }
        return URL(string: candidate)
    }
}

func prefetchNextVideos(at index: Int, urls: [URL]) {
    let nextURLs = Array(urls.suffix(from: index + 1).prefix(3))
    for url in nextURLs {
        let asset = AVURLAsset(url: url)
        asset.loadValuesAsynchronously(forKeys: ["playable"]) { /* primed */ }
    }
}
