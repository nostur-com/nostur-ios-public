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

func prefetchNextVideos(at index: Int, urls: [URL]) {
    let nextURLs = Array(urls.suffix(from: index + 1).prefix(3))
    for url in nextURLs {
        let asset = AVURLAsset(url: url)
        asset.loadValuesAsynchronously(forKeys: ["playable"]) { /* primed */ }
    }
}
