//
//  EmbeddedAVPlayerRepresentable.swift
//  (was) VideoViewurReprestable.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/03/2025.
//

import SwiftUI
import AVKit
import Combine


struct EmbeddedAVPlayerRepresentable: UIViewRepresentable {
    typealias UIViewType = UIView
    
    private var asset: AVAsset?
    private var url: URL
    @Binding var timeControlStatus: AVPlayer.TimeControlStatus
    @Binding var isMuted: Bool
    
    init(url: URL, asset: AVAsset? = nil, timeControlStatus: Binding<AVPlayer.TimeControlStatus>, isMuted: Binding<Bool>) {
        self.asset = asset
        self.url = url
        _timeControlStatus = timeControlStatus
        _isMuted = isMuted
    }

    func makeUIView(context: Context) -> UIView {
        let avpc = AVPlayerViewController()
        let playerItem = if let asset {
            AVPlayerItem(asset: asset)
        }
        else {
            AVPlayerItem(url: url)
        }

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
        avpc.updatesNowPlayingInfoCenter = true
        context.coordinator.avpc = avpc
        context.coordinator.cancellable = player
            .publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { newStatus in
                if timeControlStatus != newStatus && !context.coordinator.playStateIsChanging {
                    self.timeControlStatus = newStatus
                }
                else if timeControlStatus == newStatus && context.coordinator.playStateIsChanging {
                    context.coordinator.playStateIsChanging = false
                }
            }

        avpc.view.isUserInteractionEnabled = true
        
        try? AVAudioSession.sharedInstance().setActive(true)
        
        return avpc.view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if timeControlStatus == .playing && context.coordinator.avpc?.player?.timeControlStatus != .playing {
            try? AVAudioSession.sharedInstance().setActive(true)
            context.coordinator.playStateIsChanging = true
            context.coordinator.avpc?.player?.isMuted = isMuted
            context.coordinator.avpc?.player?.play()
        }
        else if timeControlStatus == .paused && context.coordinator.avpc?.player?.timeControlStatus != .paused {
            context.coordinator.playStateIsChanging = true
            context.coordinator.avpc?.player?.isMuted = isMuted
            context.coordinator.avpc?.player?.pause()
        }
    }
    
    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var avpc: AVPlayerViewController?
        var parent: EmbeddedAVPlayerRepresentable
        var cancellable: AnyCancellable?
        
        // updateUIView() and player.publisher(for: \.timeControlStatus) get stuck in a loop so use this flag to know whats up
        var playStateIsChanging = false
        
        init(parent: EmbeddedAVPlayerRepresentable) {
            self.parent = parent
        }
        
        deinit {
            avpc?.player?.replaceCurrentItem(with: nil)
            cancellable?.cancel()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
}
