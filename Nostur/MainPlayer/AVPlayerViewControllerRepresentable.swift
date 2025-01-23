//
//  AVPlayerViewControllerRepresentable.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/01/2025.
//

import SwiftUI
import Combine
import AVKit

struct AVPlayerViewControllerRepresentable: UIViewControllerRepresentable {
    // MARK: - Bindings
    @Binding var player: AVPlayer
    @Binding var isPlaying: Bool
    @Binding var showsPlaybackControls: Bool
    @Binding var viewMode: AnyPlayerViewMode
    

    // MARK: - UIViewControllerRepresentable Methods
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        print("makeUIViewController")
        let controller = AVPlayerViewController()
        controller.player = player
        controller.modalPresentationStyle = .fullScreen
        controller.delegate = context.coordinator // Optional: if you want to handle delegate methods
        controller.showsPlaybackControls = showsPlaybackControls
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.allowsPictureInPicturePlayback = true
        controller.entersFullScreenWhenPlaybackBegins = true
        controller.exitsFullScreenWhenPlaybackEnds = true

//        controller.videoGravity = .resizeAspectFill
        
        
        if viewMode == .fullscreen {
            
            player.playImmediately(atRate: 1.0)
//            controller.videoGravity = .resizeAspectFill
            player.play()
//            controller.modalPresentationStyle = .fullScreen
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // SwiftUI to UIKit
        // Update properties of the UIViewController based on the latest SwiftUI state.
        print("updateUIViewController")
        uiViewController.player = player
        if isPlaying {
            if player.timeControlStatus != .playing {
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
        
        uiViewController.showsPlaybackControls = showsPlaybackControls
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
        var parent: AVPlayerViewControllerRepresentable
        var timeObserverToken: Any?
        
        init(parent: AVPlayerViewControllerRepresentable) {
            self.parent = parent
            super.init()
            addObservers()
        }
        
        deinit {
            if let token = timeObserverToken {
                parent.player.removeTimeObserver(token)
            }
            removeObservers()
        }
        
        // Add observers to monitor playback status
        func addObservers() {
            parent.player.addObserver(self, forKeyPath: "timeControlStatus", options: [.new, .initial], context: nil)
            
            // Optionally, observe when the video finishes playing
            NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying),
                                                   name: .AVPlayerItemDidPlayToEndTime, object: parent.player.currentItem)
        }
        
        func removeObservers() {
            parent.player.removeObserver(self, forKeyPath: "timeControlStatus")
            NotificationCenter.default.removeObserver(self)
        }
        
        // Observe changes in the player's status
        override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                   change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == "timeControlStatus" {
                DispatchQueue.main.async {
                    self.parent.isPlaying = self.parent.player.timeControlStatus == .playing
                }
            }
        }
        
        // Handle video playback completion
        @objc func playerDidFinishPlaying(notification: Notification) {
            DispatchQueue.main.async {
                self.parent.isPlaying = false
            }
        }
    }
}
