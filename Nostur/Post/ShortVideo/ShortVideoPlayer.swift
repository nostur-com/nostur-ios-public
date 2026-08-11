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
    @Binding var isMuted: Bool
    

    // Reuse or create player
    private static func getPlayer(for url: URL) -> AVPlayer {
        ShortVideoPlayerPool.shared.queue.sync {
            // Try to reuse an existing player with the same URL
            if let existing = ShortVideoPlayerPool.shared.playerPool.first(where: { ($0.currentItem?.asset as? AVURLAsset)?.url == url }) {
                if let index = ShortVideoPlayerPool.shared.playerPool.firstIndex(of: existing) {
                    ShortVideoPlayerPool.shared.playerPool.remove(at: index)
                }
                existing.seek(to: .zero)
                existing.volume = 1.0
                return existing
            }
            
            // Create new player with buffering optimizations
            let player = AVPlayer()
            player.isMuted = true
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
        ShortVideoPlayerPool.shared.queue.async {
            player.pause()
            player.replaceCurrentItem(with: nil)
            ShortVideoPlayerPool.shared.playerPool.append(player)
            // Keep pool reasonable size
            if ShortVideoPlayerPool.shared.playerPool.count > 8 {
                ShortVideoPlayerPool.shared.playerPool.removeFirst()
            }
        }
    }
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .black
        if #available(iOS 18.0, *) {
            controller.allowsVideoFrameAnalysis = false
        }
        
        let playbackURLs = shortVideoPlaybackURLs(for: url)

        // Critical for smoothness
        controller.player = Self.getPlayer(for: playbackURLs[0])
        controller.player?.isMuted = isMuted

        context.coordinator.playerController = controller
        context.coordinator.player = controller.player
        context.coordinator.updatePlaybackURLs(playbackURLs)
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        guard let player = uiViewController.player else { return }

        context.coordinator.updatePlaybackURLs(shortVideoPlaybackURLs(for: url))
        
        player.isMuted = isMuted
        
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

        private var playbackURLs: [URL] = []
        private var playbackURLIndex = 0
        private var itemStatusObservation: NSKeyValueObservation?
        private var didPlayToEndObserver: NSObjectProtocol?
        private var failedToPlayToEndObserver: NSObjectProtocol?
        
        init(isPlaying: Binding<Bool>) {
            self._isPlaying = isPlaying
        }

        func updatePlaybackURLs(_ urls: [URL]) {
            guard !urls.isEmpty else { return }
            guard playbackURLs != urls else { return }

            playbackURLs = urls
            playbackURLIndex = 0
            replaceCurrentItemIfNeeded(with: urls[0])
            observeCurrentItem()
        }

        private func replaceCurrentItemIfNeeded(with url: URL) {
            guard let player else { return }
            let currentURL = (player.currentItem?.asset as? AVURLAsset)?.url
            guard currentURL != url else { return }

            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 10
            player.replaceCurrentItem(with: item)
        }

        private func observeCurrentItem() {
            itemStatusObservation?.invalidate()
            if let didPlayToEndObserver {
                NotificationCenter.default.removeObserver(didPlayToEndObserver)
            }
            if let failedToPlayToEndObserver {
                NotificationCenter.default.removeObserver(failedToPlayToEndObserver)
            }

            guard let item = player?.currentItem else { return }

            itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
                guard let self, let item, item.status == .failed else { return }
                DispatchQueue.main.async {
                    self.advanceAfterFailure(of: item)
                }
            }

            didPlayToEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self, weak item] _ in
                guard let self, let item, self.player?.currentItem === item else { return }
                self.player?.seek(to: .zero)
                if self.isPlaying {
                    self.player?.play()
                }
            }

            failedToPlayToEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self, weak item] _ in
                guard let self, let item else { return }
                self.advanceAfterFailure(of: item)
            }
        }

        private func advanceAfterFailure(of failedItem: AVPlayerItem) {
            guard player?.currentItem === failedItem else { return }
            let nextIndex = playbackURLIndex + 1
            guard playbackURLs.indices.contains(nextIndex) else { return }

            playbackURLIndex = nextIndex
            replaceCurrentItemIfNeeded(with: playbackURLs[nextIndex])
            observeCurrentItem()

            if isPlaying {
                player?.playImmediately(atRate: 1.0)
            }
        }

        fileprivate func stopObserving() {
            itemStatusObservation?.invalidate()
            itemStatusObservation = nil
            if let didPlayToEndObserver {
                NotificationCenter.default.removeObserver(didPlayToEndObserver)
                self.didPlayToEndObserver = nil
            }
            if let failedToPlayToEndObserver {
                NotificationCenter.default.removeObserver(failedToPlayToEndObserver)
                self.failedToPlayToEndObserver = nil
            }
        }
        
        deinit {
            stopObserving()
            if let player = player {
                ShortVideoPlayer.returnPlayer(player)
            }
        }
    }
    
    // Clean up on disappear
    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        uiViewController.player?.pause()
        coordinator.stopObserving()
    }
}


class ShortVideoPlayerPool {
    public let queue = DispatchQueue(label: "com.nostur.playerpool")
    public var playerPool: [AVPlayer] = []
    
    private init() { }
    static let shared: ShortVideoPlayerPool = .init()
}
