//
//  VideoHelpers.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/05/2023.
//

import Foundation
import AVFoundation

func getVideoDimensions(asset: AVAsset) async -> CGSize? {
    // Get the video track
    guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
        L.og.debug("getVideoDimensions: Unable to get video track")
        return nil
    }

    // Get the natural size of the video track
    guard let naturalSize = try? await videoTrack.load(.naturalSize) else {
        L.og.debug("getVideoDimensions: Unable to get naturalSize of video track")
        return nil
    }

    // Get the preferred transform to handle any video orientation
    guard let preferredTransform = try? await videoTrack.load(.preferredTransform) else {
        L.og.debug("getVideoDimensions: Unable to get preferredTransform of video track")
        return nil
    }

    // Calculate the corrected video dimensions considering the orientation
    let correctedSize = CGSize(
        width: abs(CGFloat(preferredTransform.a) * naturalSize.width + CGFloat(preferredTransform.c) * naturalSize.height),
        height: abs(CGFloat(preferredTransform.b) * naturalSize.width + CGFloat(preferredTransform.d) * naturalSize.height)
    )

    return correctedSize
}

func getScaledVideoDimensions(videoSize:CGSize, availableWidth:CGFloat, maxHeight:CGFloat = 600) -> CGSize {

    let videoAspect = videoSize.width / videoSize.height
    
    let scaleH = videoSize.height/maxHeight
    let scaleW = videoSize.width/availableWidth
    
    if scaleH <= 1 && scaleW <= 1 { // w and h both fit on screen
        // return without scaling
        L.og.info("getScaledVideoDimensions: availableWidth:\(availableWidth) - maxHeight: \(maxHeight) videoSize:\(videoSize.width)x\(videoSize.height) no scaling needed ")
        return CGSize(width: videoSize.width, height: videoSize.height)
    }
    
    if scaleW > scaleH { // Width too big, scale down:
        let scaledWidth = videoSize.width / scaleW
        let scaledHeight = scaledWidth / videoAspect
        L.og.info("getScaledVideoDimensions: availableWidth:\(availableWidth) - maxHeight: \(maxHeight) videoSize:\(videoSize.width)x\(videoSize.height) --scaled--> \(scaledWidth)x\(scaledHeight) ")
        return CGSize(width: scaledWidth, height: scaledHeight)
    }
    
    // else it means height is too big, scale down:
    let scaledHeight = videoSize.height / scaleH
    let scaledWidth = scaledHeight * videoAspect
    
    L.og.info("getScaledVideoDimensions: availableWidth:\(availableWidth) - maxHeight: \(maxHeight) videoSize:\(videoSize.width)x\(videoSize.height) --scaled--> \(scaledWidth)x\(scaledHeight) ")
    return CGSize(width: scaledWidth, height: scaledHeight)
}

func getVideoLength(asset:AVAsset) async -> String? {
    guard let duration = try? await asset.load(.duration) else {
        L.og.debug("getVideoLength: Unable to load udration")
        return nil
    }
    
    let seconds = CMTimeGetSeconds(duration)
    let secondsText = String(format: "%02d", Int(seconds) % 60)
    let minutesText = String(format: "%02d", Int(seconds) / 60)
    return "\(minutesText):\(secondsText)"
}
