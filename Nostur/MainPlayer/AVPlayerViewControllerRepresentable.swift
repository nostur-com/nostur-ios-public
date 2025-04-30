//
//  AVPlayerViewControllerRepresentable.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/01/2025.
//

import SwiftUI
import Combine
import AVKit

struct AVPlayerViewControllerRepresentable: UIViewRepresentable {
    // TODO: UIViewRepresentable or ViewControllerRepresentable?
    // Moved from UIViewControllerRepresentable to UIViewRepresentable as hack to fix issues with UIViewControllerRepresentable in SwiftUI in UIViewControllerRepresentable (SmoothList/Table). Since we are no longer using that maybe move back to UIViewControllerRepresentable?
    
    typealias UIViewType = UIView
    
    // MARK: - Bindings
    @Binding var player: AVPlayer
    @Binding var isPlaying: Bool
    @Binding var showsPlaybackControls: Bool
    @Binding var viewMode: AnyPlayerViewMode
    

    // MARK: - UIViewControllerRepresentable Methods
    func makeUIView(context: Context) -> UIView {
        let avpc = AVPlayerViewController()
        
        player.isMuted = false
        avpc.player = player

        avpc.exitsFullScreenWhenPlaybackEnds = false
//        if viewMode == .fullscreen {
//            avpc.videoGravity = .resizeAspectFill
//        }
//        else {
//            avpc.videoGravity = .resizeAspect
//        }
        
        // Apply audio-only settings
        applyAudioOnlySettings(to: avpc)
        
        avpc.allowsPictureInPicturePlayback = true
        avpc.delegate = context.coordinator
        avpc.showsPlaybackControls = showsPlaybackControls
        avpc.canStartPictureInPictureAutomaticallyFromInline = true
        avpc.updatesNowPlayingInfoCenter = true
        context.coordinator.avpc = avpc

        avpc.view.isUserInteractionEnabled = true
        
        try? AVAudioSession.sharedInstance().setActive(true)
        
        let swipeDown = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.respondToSwipeGesture))
        swipeDown.direction = UISwipeGestureRecognizer.Direction.down
        avpc.view.addGestureRecognizer(swipeDown)
        
        if isPlaying && player.timeControlStatus != .playing {
            player.play()
        }
        
        return avpc.view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {        
        // SwiftUI to UIKit
        // Update properties of the UIViewController based on the latest SwiftUI state.
        if isPlaying && player.timeControlStatus == .paused {
            player.play()
        }
        else if !isPlaying && player.timeControlStatus != .paused {
            player.pause()
        }
        
        
        if let avpc = context.coordinator.avpc, avpc.showsPlaybackControls != showsPlaybackControls {
            avpc.showsPlaybackControls = showsPlaybackControls
        }
        
//        if AnyPlayerModel.shared.timeControlStatus == .playing && player.timeControlStatus != .playing {
//            print("updateUIView 1")
//            try? AVAudioSession.sharedInstance().setActive(true)
//            isPlaying = true
//            AnyPlayerModel.shared.playStateIsChanging = true
//            player.play()
//        }
//        else if AnyPlayerModel.shared.timeControlStatus == .paused && AnyPlayerModel.shared.timeControlStatus != .paused {
//            print("updateUIView 2")
//            AnyPlayerModel.shared.playStateIsChanging = true
//            player.pause()
//        }
        
        // Update audio-only mode
        if let avpc = context.coordinator.avpc {
            applyAudioOnlySettings(to: avpc)
        }
    }
    
    // Helper to apply audio-only settings
    private func applyAudioOnlySettings(to avpc: AVPlayerViewController) {
        let isHidden = viewMode == .audioOnlyBar
        avpc.view.isHidden = isHidden
        if isHidden {
            // If presenting video with AVPlayerViewController
            avpc.player = nil

            // If presenting video with AVPlayerLayer
            //playerLayer.player = nil
        }
        else {
            avpc.player = player
        }
    }
    
    // MARK: - Coordinator Creation
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    // MARK: - Coordinator
    // Use the Coordinator to communicate events back to SwiftUI.
    // Implement any delegate methods or communication logic within the Coordinator.
    // UIKit to SwiftUI
    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var avpc: AVPlayerViewController?
        var parent: AVPlayerViewControllerRepresentable
        
        init(parent: AVPlayerViewControllerRepresentable) {
            self.parent = parent
            super.init()
        }
        
        @objc func respondToSwipeGesture(_ swipe: UISwipeGestureRecognizer) {
            if AnyPlayerModel.shared.availableViewModes.contains(.overlay) {
                AnyPlayerModel.shared.viewMode = .overlay
            }
            else {
                Task { @MainActor in
                    AnyPlayerModel.shared.close()
                }
            }
        }
    }
}
