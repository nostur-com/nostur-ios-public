//
//  VideoHelpers.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/05/2023.
//

import Foundation
import AVFoundation
import UIKit

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

func getVideoFirstFrame(asset:AVAsset) async -> UIImage? {
    let imageGenerator = AVAssetImageGenerator(asset: asset)
    imageGenerator.appliesPreferredTrackTransform = true
    
    guard let cgImage = try? imageGenerator.copyCGImage(at: CMTime(seconds: 0, preferredTimescale: 1), actualTime: nil)
    else { return nil }
                                                     
    return await UIImage(cgImage: cgImage).byPreparingForDisplay()
}
