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

    private var firstFrameCache: NSCache<NSString, CachedFirstFrame>
    public var failedFirstFrameUrls = FIFOLimitedSet(maxSize: 20)

    private init() {
        self.firstFrameCache = NSCache<NSString, CachedFirstFrame>()
        self.firstFrameCache.countLimit = 10
    }
    
    public func getFirstFrame(url: String) -> CachedFirstFrame? {
        return firstFrameCache.object(forKey: url as NSString)
    }
    
    public func set(url: String, firstFrame: CachedFirstFrame) {
        firstFrameCache.setObject(firstFrame, forKey: url as NSString)
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
