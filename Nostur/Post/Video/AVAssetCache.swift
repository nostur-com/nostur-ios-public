//
//  AVAssetCache.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/03/2025.
//

import SwiftUI
import NukeUI
import Nuke
import NukeVideo
import AVFoundation

class AVAssetCache {
    static let shared = AVAssetCache()
    
    private var cache: NSCache<NSString, CachedVideo>
    private var firstFrameCache: NSCache<NSString, CachedFirstFrame>
    public var failedFirstFrameUrls = FIFOLimitedSet(maxSize: 20)

    private init() {
        self.cache = NSCache<NSString, CachedVideo>()
        self.cache.countLimit = 5
        self.firstFrameCache = NSCache<NSString, CachedFirstFrame>()
        self.firstFrameCache.countLimit = 10
    }

    public func get(url: String) -> CachedVideo? {
        return cache.object(forKey: url as NSString)
    }
    
    public func set(url: String, asset: CachedVideo) {
        cache.setObject(asset, forKey: url as NSString)
    }
    
    public func getFirstFrame(url: String) -> CachedFirstFrame? {
        return firstFrameCache.object(forKey: url as NSString)
    }
    
    public func set(url: String, firstFrame: CachedFirstFrame) {
        firstFrameCache.setObject(firstFrame, forKey: url as NSString)
    }
}

class CachedVideo: Identifiable {
    var id: String { url }
    let url: String
    let asset: AVAsset
    let dimensions: CGSize
    let scaledDimensions: CGSize
    var duration: CMTime?
    var firstFrame: UIImage? = nil
    
    public init(url: String, asset: AVAsset, dimensions: CGSize, scaledDimensions: CGSize, duration: CMTime?, firstFrame: UIImage? = nil) {
        self.url = url
        self.asset = asset
        self.dimensions = dimensions
        self.scaledDimensions = scaledDimensions
        self.duration = duration
        self.firstFrame = firstFrame
    }
    
    public var isPortrait: Bool {
        dimensions.height > dimensions.width
    }
    
    public var durationString: String? {
        guard let duration else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        let secondsText = String(format: "%02d", Int(seconds) % 60)
        let minutesText = String(format: "%02d", Int(seconds) / 60)
        return "\(minutesText):\(secondsText)"
    }
}

class CachedFirstFrame: Identifiable {
    var id: String { url }
    let url: String
    var uiImage: UIImage
    var dimensions: CGSize?
    var duration: CMTime?
    
    
    public init(url: String, uiImage: UIImage, dimensions: CGSize?, duration: CMTime?) {
        self.url = url
        self.uiImage = uiImage
        self.dimensions = dimensions
        self.duration = duration
        
    }
    
    public var isPortrait: Bool {
        guard let dimensions else { return true }
        return dimensions.height > dimensions.width
    }
    
    public var durationString: String? {
        guard let duration else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        let secondsText = String(format: "%02d", Int(seconds) % 60)
        let minutesText = String(format: "%02d", Int(seconds) / 60)
        return "\(minutesText):\(secondsText)"
    }
}
