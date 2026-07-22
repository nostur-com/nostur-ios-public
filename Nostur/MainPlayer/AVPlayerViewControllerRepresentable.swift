//
//  AVPlayerViewControllerRepresentable.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/01/2025.
//

import SwiftUI
import Combine
import AVKit

/// Hosts `AVPlayerViewController` for OverlayPlayer.
/// Custom chrome sets `showsPlaybackControls = false`; play/pause is driven by the `isPlaying` binding.
struct AVPlayerViewControllerRepresentable: UIViewControllerRepresentable {
    
    typealias UIViewControllerType = AVPlayerViewController
    
    @Binding var player: AVPlayer
    @Binding var isPlaying: Bool
    @Binding var showsPlaybackControls: Bool
    @Binding var viewMode: AnyPlayerViewMode
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let avpc = AVPlayerViewController()
        
        player.isMuted = false
        avpc.player = player
        avpc.exitsFullScreenWhenPlaybackEnds = false
        avpc.videoGravity = .resizeAspect
        
        applyAudioOnlySettings(to: avpc)
        
        avpc.allowsPictureInPicturePlayback = true
        avpc.delegate = context.coordinator
        // Custom OverlayPlayer chrome owns controls — keep native chrome off.
        avpc.showsPlaybackControls = false
        avpc.canStartPictureInPictureAutomaticallyFromInline = true
        avpc.updatesNowPlayingInfoCenter = false
        context.coordinator.avpc = avpc
        
        avpc.view.backgroundColor = .black
        avpc.view.isUserInteractionEnabled = true
        
        let swipeDown = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.respondToSwipeGesture))
        swipeDown.direction = .down
        avpc.view.addGestureRecognizer(swipeDown)
        
        startPlaybackIfNeeded(on: avpc)
        
        return avpc
    }
    
    func updateUIViewController(_ avpc: AVPlayerViewController, context: Context) {
        context.coordinator.avpc = avpc
        
        // Only pause when we intentionally stopped — never while buffering
        // (.waitingToPlayAtSpecifiedRate is != .paused and used to cancel live HLS startup).
        if isPlaying {
            if player.timeControlStatus != .playing {
                player.play()
            }
        }
        else if player.rate != 0 || player.timeControlStatus == .playing {
            player.pause()
        }
        
        avpc.showsPlaybackControls = false
        // Keep player assigned (important after item replace / reopen).
        if viewMode != .audioOnlyBar, avpc.player !== player {
            avpc.player = player
        }
        applyAudioOnlySettings(to: avpc)
        startPlaybackIfNeeded(on: avpc)
    }
    
    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        // Always release on dismantle so the next mount can attach cleanly on device.
        uiViewController.delegate = nil
        uiViewController.player = nil
        uiViewController.view.gestureRecognizers?.removeAll()
        coordinator.avpc = nil
    }
    
    private func applyAudioOnlySettings(to avpc: AVPlayerViewController) {
        let isHidden = viewMode == .audioOnlyBar
        avpc.view.isHidden = isHidden
        if isHidden {
            avpc.player = nil
        }
        else if avpc.player !== player {
            avpc.player = player
        }
    }
    
    private func startPlaybackIfNeeded(on avpc: AVPlayerViewController) {
        guard isPlaying, viewMode != .audioOnlyBar else { return }
        if avpc.player !== player {
            avpc.player = player
        }
        guard player.timeControlStatus != .playing else { return }
        
        if AnyPlayerModel.shared.isStream {
            player.playImmediately(atRate: 1.0)
        }
        else {
            player.play()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var avpc: AVPlayerViewController?
        var parent: AVPlayerViewControllerRepresentable
        
        init(parent: AVPlayerViewControllerRepresentable) {
            self.parent = parent
            super.init()
        }
        
        @objc func respondToSwipeGesture(_ swipe: UISwipeGestureRecognizer) {
            Task { @MainActor in
                switch AnyPlayerModel.shared.viewMode {
                case .detailstream where AnyPlayerModel.shared.availableViewModes.contains(.overlay):
                    AnyPlayerModel.shared.viewMode = .overlay
                case .fullscreen:
                    restorePortraitOrientation()
                    AnyPlayerModel.shared.close()
                default:
                    break
                }
            }
        }
        
        private func restorePortraitOrientation() {
#if !targetEnvironment(macCatalyst)
            AppDelegate.supportedOrientations = .allButUpsideDown
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
            UINavigationController.attemptRotationToDeviceOrientation()
            
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
            else { return }
            
            if #available(iOS 16.0, *) {
                windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
#if DEBUG
                    L.og.debug("Portrait rotation request failed: \(error.localizedDescription)")
#endif
                }
            }
#endif
        }
    }
}
