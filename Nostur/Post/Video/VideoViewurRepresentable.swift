//
//  VideoViewurReprestable.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/06/2023.
//

import SwiftUI
import AVKit

struct VideoViewurRepresentable: UIViewRepresentable {
    typealias UIViewType = UIView
    
    private var asset:AVAsset
    private var url:URL
    @Binding var isPlaying:Bool
    @Binding var isMuted:Bool
    
    init(url:URL, asset: AVAsset, isPlaying:Binding<Bool>, isMuted:Binding<Bool>) {
        self.asset = asset
        self.url = url
        _isPlaying = isPlaying
        _isMuted = isMuted
    }

    func makeUIView(context: Context) -> UIView {
        let avpc = AVPlayerViewController()
        let playerItem = AVPlayerItemCache.shared.get(url: url.absoluteString, asset: asset)
        let player = AVQueuePlayer(playerItem: playerItem)
        player.isMuted = isMuted
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .pause
        avpc.player = player
        avpc.exitsFullScreenWhenPlaybackEnds = false
        avpc.videoGravity = .resizeAspect
        avpc.allowsPictureInPicturePlayback = true
        avpc.delegate = context.coordinator
        avpc.showsPlaybackControls = true
        avpc.canStartPictureInPictureAutomaticallyFromInline = true
        context.coordinator.avpc = avpc

        avpc.view.isUserInteractionEnabled = true
        return avpc.view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update the view if needed...
        
        uiView.isUserInteractionEnabled = true
        if isPlaying {
            do { try AVAudioSession.sharedInstance().setActive(true) }
            catch { }
            context.coordinator.avpc?.player?.isMuted = isMuted
            context.coordinator.avpc?.player?.play()
        }
        else {
            context.coordinator.avpc?.player?.isMuted = isMuted
            context.coordinator.avpc?.player?.pause()
        }
    }
    
    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var avpc:AVPlayerViewController?
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}
