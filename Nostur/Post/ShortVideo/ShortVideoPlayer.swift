//
//  ShortVideoPlayer.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/11/2025.
//

import Foundation
import SwiftUI
import AVKit

// MARK: - Reusable Smooth Video Player (TikTok-style)
struct ShortVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    @Binding var isPlaying: Bool
    
    // Shared player pool to recycle AVPlayers (critical for performance)
    private static var playerPool: [AVPlayer] = []
    private static let queue = DispatchQueue(label: "com.nostur.playerpool")
    
    // Reuse or create player
    private static func getPlayer(for url: URL) -> AVPlayer {
        queue.sync {
            // Try to reuse an existing player with the same URL
            if let existing = playerPool.first(where: { ($0.currentItem?.asset as? AVURLAsset)?.url == url }) {
                if let index = playerPool.firstIndex(of: existing) {
                    playerPool.remove(at: index)
                }
                existing.seek(to: .zero)
                existing.volume = 1.0
                return existing
            }
            
            // Create new player with buffering optimizations
            let player = AVPlayer()
            player.isMuted = false
            player.automaticallyWaitsToMinimizeStalling = true
            
            // Aggressive prefetching
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            
            // Pre-buffer as much as possible
            player.currentItem?.preferredForwardBufferDuration = 10
            
            return player
        }
    }
    
    // Return player to pool when done
    private static func returnPlayer(_ player: AVPlayer) {
        queue.async {
            player.pause()
            player.replaceCurrentItem(with: nil)
            playerPool.append(player)
            // Keep pool reasonable size
            if playerPool.count > 8 {
                playerPool.removeFirst()
            }
        }
    }
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .black
        
        // Critical for smoothness
        controller.player = Self.getPlayer(for: url)
        
        // Observe when video reaches end → loop
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: controller.player?.currentItem,
            queue: .main
        ) { _ in
            controller.player?.seek(to: .zero)
            if isPlaying {
                controller.player?.play()
            }
        }
        
        context.coordinator.playerController = controller
        context.coordinator.player = controller.player
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        guard let player = uiViewController.player else { return }
        
        if isPlaying {
            player.playImmediately(atRate: 1.0)  // Bypasses some buffering delays
        } else {
            player.pause()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(isPlaying: $isPlaying)
    }
    
    class Coordinator: NSObject {
        var player: AVPlayer?
        var playerController: AVPlayerViewController?
        @Binding var isPlaying: Bool
        
        init(isPlaying: Binding<Bool>) {
            self._isPlaying = isPlaying
        }
        
        deinit {
            if let player = player {
                ShortVideoPlayer.returnPlayer(player)
            }
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    // Clean up on disappear
    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        uiViewController.player?.pause()
    }
}
