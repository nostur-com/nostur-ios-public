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
        
        avpc.player = player
        avpc.exitsFullScreenWhenPlaybackEnds = false
        avpc.videoGravity = .resizeAspect
        avpc.allowsPictureInPicturePlayback = true
        avpc.delegate = context.coordinator
        avpc.showsPlaybackControls = true
        avpc.canStartPictureInPictureAutomaticallyFromInline = true
        avpc.updatesNowPlayingInfoCenter = true
//        avpc.setValue(false, forKey: "canHidePlaybackControls")
        context.coordinator.avpc = avpc

        avpc.view.isUserInteractionEnabled = true
        return avpc.view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // SwiftUI to UIKit
        // Update properties of the UIViewController based on the latest SwiftUI state.
        print("updateUIViewController")
//        context.coordinator.avpc?.player = player
        if isPlaying {
            if player.timeControlStatus != .playing {
                uiView.isUserInteractionEnabled = true
                try? AVAudioSession.sharedInstance().setActive(true)
                player.play()
            }
        } else {
            if player.timeControlStatus == .playing {
                player.pause()
            }
        }
        
        if viewMode == .fullscreen {
//            uiViewController.videoGravity = .resizeAspectFill
//            uiViewController.modalPresentationStyle = .fullScreen
        }
        
        context.coordinator.avpc?.showsPlaybackControls = showsPlaybackControls
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
        var timeObserverToken: Any?
        
        init(parent: AVPlayerViewControllerRepresentable) {
            self.parent = parent
            super.init()
//            addObservers()
        }
//        
//        deinit {
//            if let token = timeObserverToken {
//                parent.player?.removeTimeObserver(token)
//            }
//            removeObservers()
//        }
        
//        // Add observers to monitor playback status
//        func addObservers() {
//            guard let player = parent.player  else { return }
//            player.addObserver(self, forKeyPath: "timeControlStatus", options: [.new, .initial], context: nil)
//            
//            // Optionally, observe when the video finishes playing
//            NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying),
//                                                   name: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)
//        }
        
//        func removeObservers() {
//            guard let player = parent.player  else { return }
//            player.removeObserver(self, forKeyPath: "timeControlStatus")
//            NotificationCenter.default.removeObserver(self)
//        }
        
        // Observe changes in the player's status
//        override func observeValue(forKeyPath keyPath: String?, of object: Any?,
//                                   change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
//            guard let player = parent.player  else { return }
//            if keyPath == "timeControlStatus" {
//                DispatchQueue.main.async { [weak self] in
//                    self?.parent.isPlaying = player.timeControlStatus == .playing
//                }
//            }
//        }
        
//        // Handle video playback completion
//        @objc func playerDidFinishPlaying(notification: Notification) {
//            DispatchQueue.main.async { [weak self] in
//                self?.parent.isPlaying = false
//            }
//        }
    }
}
