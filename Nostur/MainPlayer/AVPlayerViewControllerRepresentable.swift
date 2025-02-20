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
        avpc.allowsPictureInPicturePlayback = true
        avpc.delegate = context.coordinator
        avpc.showsPlaybackControls = true
        avpc.canStartPictureInPictureAutomaticallyFromInline = true
        avpc.updatesNowPlayingInfoCenter = true
        context.coordinator.avpc = avpc

        avpc.view.isUserInteractionEnabled = true
        
        try? AVAudioSession.sharedInstance().setActive(true)
        
        return avpc.view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // SwiftUI to UIKit
        // Update properties of the UIViewController based on the latest SwiftUI state.
//        print("updateUIViewController")
        if isPlaying {
            if player.timeControlStatus != .playing {
                uiView.isUserInteractionEnabled = true
                player.play()
                try? AVAudioSession.sharedInstance().setActive(true)
            }
        }
        else {
            if player.timeControlStatus == .playing {
                player.pause()
            }
        }
        
//        if viewMode == .fullscreen && context.coordinator.avpc?.videoGravity != .resizeAspectFill {
//            context.coordinator.avpc?.videoGravity = .resizeAspectFill
//        }
//        else {
//            context.coordinator.avpc?.videoGravity = .resizeAspect
//        }
        
//        context.coordinator.avpc?.showsPlaybackControls = showsPlaybackControls
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
    }
}
