//
//  AVPlayerViewControllerRepresentable.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/01/2025.
//

import SwiftUI
import Combine
import AVKit
import AVFoundation

/// Hosts `AVPlayerViewController` for OverlayPlayer.
/// Custom chrome sets `showsPlaybackControls = false`; play/pause is driven by the `isPlaying` binding.
/// On Mac Catalyst, video + system PiP use a dedicated `AVPlayerLayer` host (AVPC has no usable layer for PiP).
struct AVPlayerViewControllerRepresentable: UIViewControllerRepresentable {
    
    typealias UIViewControllerType = AVPlayerViewController
    
    @Binding var player: AVPlayer
    @Binding var isPlaying: Bool
    @Binding var showsPlaybackControls: Bool
    @Binding var viewMode: AnyPlayerViewMode
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let avpc = AVPlayerViewController()
        
        player.isMuted = false
        avpc.exitsFullScreenWhenPlaybackEnds = false
        avpc.videoGravity = .resizeAspect
        
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
        
        // On Mac, drive video + system PiP from our own AVPlayerLayer. AVPlayerViewController
        // does not expose a usable player layer for AVPictureInPictureController.
        if IS_CATALYST {
            context.coordinator.rebuildCatalystSurface(player: player, reason: "make")
            avpc.player = nil
        }
        else {
            avpc.player = player
            applyAudioOnlySettings(to: avpc)
        }
        
        startPlaybackIfNeeded(on: avpc)
        context.coordinator.lastIsPlaying = isPlaying
        context.coordinator.lastViewMode = viewMode
        context.coordinator.registerNativePiPHandlers()
        
        return avpc
    }
    
    func updateUIViewController(_ avpc: AVPlayerViewController, context: Context) {
        context.coordinator.avpc = avpc
        context.coordinator.parent = self
        
        avpc.showsPlaybackControls = false
        
        if IS_CATALYST {
            context.coordinator.syncCatalystPlayerLayer(player: player, viewMode: viewMode)
        }
        else {
            // Keep player assigned (important after item replace / reopen).
            if viewMode != .audioOnlyBar, avpc.player !== player {
                avpc.player = player
            }
            applyAudioOnlySettings(to: avpc)
        }

        let resumedFromAudioOnly = context.coordinator.lastViewMode == .audioOnlyBar && viewMode != .audioOnlyBar
        let resumedFromNativePiP = context.coordinator.wasNativePiPActive && !AnyPlayerModel.shared.isNativePictureInPictureActive
        if isPlaying && (!context.coordinator.lastIsPlaying || resumedFromAudioOnly || resumedFromNativePiP) {
            startPlaybackIfNeeded(on: avpc)
        }
        else if !isPlaying && context.coordinator.lastIsPlaying {
            player.pause()
        }
        context.coordinator.lastIsPlaying = isPlaying
        context.coordinator.lastViewMode = viewMode
        context.coordinator.wasNativePiPActive = AnyPlayerModel.shared.isNativePictureInPictureActive
    }
    
    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        let didFinishTeardown = coordinator.teardownNativePictureInPicture()
        if didFinishTeardown {
            coordinator.unregisterNativePiPHandlers()
        }
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
        if !IS_CATALYST, avpc.player !== player {
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
    
    /// UIView whose layer is an `AVPlayerLayer` — required for system PiP on Mac.
    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    
    class Coordinator: NSObject, AVPlayerViewControllerDelegate, AVPictureInPictureControllerDelegate {
        var avpc: AVPlayerViewController?
        var parent: AVPlayerViewControllerRepresentable
        var lastIsPlaying = false
        var lastViewMode: AnyPlayerViewMode?
        /// Tracks previous PiP flag so `updateUIViewController` can force-resume after stop.
        var wasNativePiPActive = false
        private var pipController: AVPictureInPictureController?
        private var didRegisterHandlers = false
        private var catalystPlayerLayerView: PlayerLayerView?
        private var possibleObservation: NSKeyValueObservation?
        private var startWhenPossible = false
        private var pipStartFallbackWorkItem: DispatchWorkItem?
        private var isTearingDown = false
        private var shouldRestoreInlineAfterPipStop = false
        private weak var pipTimelinePrimedItem: AVPlayerItem?
        private var isPrimingPipTimeline = false
        private var pipTimelinePrimingGeneration = 0
        private enum PictureInPictureState {
            case idle
            case starting
            case active
            case stopping
        }
        private var pictureInPictureState: PictureInPictureState = .idle
        
        init(parent: AVPlayerViewControllerRepresentable) {
            self.parent = parent
            super.init()
        }
        
        func registerNativePiPHandlers() {
            guard !didRegisterHandlers else { return }
            didRegisterHandlers = true
            AnyPlayerModel.shared.nativePictureInPictureHandlerOwner = self
            AnyPlayerModel.shared.startNativePictureInPictureHandler = { [weak self] in
                self?.startNativePictureInPicture() ?? false
            }
            // Keep the coordinator alive while AVKit owns a PiP window. During SwiftUI
            // dismantle this handler is the last strong owner until didStop completes.
            AnyPlayerModel.shared.stopNativePictureInPictureHandler = { [self] in
                stopNativePictureInPicture()
            }
        }
        
        func unregisterNativePiPHandlers() {
            guard didRegisterHandlers else { return }
            didRegisterHandlers = false
            // A new player host may already have replaced these handlers while an older
            // PiP session was completing its asynchronous teardown.
            guard AnyPlayerModel.shared.nativePictureInPictureHandlerOwner === self else { return }
            AnyPlayerModel.shared.nativePictureInPictureHandlerOwner = nil
            AnyPlayerModel.shared.startNativePictureInPictureHandler = nil
            AnyPlayerModel.shared.stopNativePictureInPictureHandler = nil
        }
        
        // MARK: - Catalyst player surface
        
        /// Tear down and recreate the AVPlayerLayer host + PiP controller.
        /// Required after audio-only (and other hide cycles): reusing a poisoned layer never becomes PiP-possible again.
        func rebuildCatalystSurface(player: AVPlayer, reason: String) {
            guard IS_CATALYST, let avpc else { return }
            // Releasing the controller/layer while AVKit is starting or presenting PiP can
            // orphan the system PiP window. A quick second click used to rebuild here before
            // didStart arrived, leaving a frozen window that AVKit could no longer dismiss.
            guard pictureInPictureState == .idle else {
#if DEBUG
                L.og.debug("Native PiP: ignored surface rebuild (\(reason)) while session is in flight")
#endif
                return
            }
#if DEBUG
            L.og.debug("Native PiP: rebuild surface (\(reason))")
#endif
            invalidatePipControllerOnly()
            catalystPlayerLayerView?.playerLayer.player = nil
            catalystPlayerLayerView?.removeFromSuperview()
            catalystPlayerLayerView = nil
            
            let host = PlayerLayerView()
            host.backgroundColor = .black
            host.playerLayer.videoGravity = .resizeAspect
            host.playerLayer.player = player
            host.isUserInteractionEnabled = false
            host.translatesAutoresizingMaskIntoConstraints = false
            avpc.view.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: avpc.view.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: avpc.view.trailingAnchor),
                host.topAnchor.constraint(equalTo: avpc.view.topAnchor),
                host.bottomAnchor.constraint(equalTo: avpc.view.bottomAnchor),
            ])
            catalystPlayerLayerView = host
            avpc.player = nil
            avpc.view.isHidden = false
            avpc.view.setNeedsLayout()
            avpc.view.layoutIfNeeded()
            
            installPipController(for: host.playerLayer)
        }
        
        func syncCatalystPlayerLayer(player: AVPlayer, viewMode: AnyPlayerViewMode) {
            guard IS_CATALYST, let avpc else { return }
            let isAudioOnly = viewMode == .audioOnlyBar
            let leavingAudioOnly = !isAudioOnly && lastViewMode == .audioOnlyBar
            
            if isAudioOnly {
                // Keep the AVPlayer running for audio. Do NOT nil the layer player permanently
                // mid-session without rebuilding later — that poisons PiP.
                // Hide video only; invalidate PiP controller (will rebuild on the way out).
                invalidatePipControllerOnly()
                catalystPlayerLayerView?.isHidden = true
                // Keep player attached so audio continues without reconfiguring the graph.
                // (Player stays on layer; layer is just not visible.)
                avpc.player = nil
                avpc.view.isHidden = true
                return
            }
            
            if leavingAudioOnly || catalystPlayerLayerView == nil {
                // Fresh layer after audio-only — old layer/controller often never report possible again.
                rebuildCatalystSurface(player: player, reason: leavingAudioOnly ? "leaveAudioOnly" : "missingHost")
                return
            }
            
            catalystPlayerLayerView?.isHidden = false
            if catalystPlayerLayerView?.playerLayer.player !== player {
                catalystPlayerLayerView?.playerLayer.player = player
            }
            avpc.view.isHidden = false
            avpc.player = nil
            
            if pipController == nil {
                if let layer = catalystPlayerLayerView?.playerLayer {
                    installPipController(for: layer)
                }
            }
        }
        
        /// Drop only the PiP controller (optionally keep the player layer host).
        func invalidatePipControllerOnly() {
            guard pictureInPictureState == .idle else {
#if DEBUG
                L.og.debug("Native PiP: deferred controller invalidation while session is in flight")
#endif
                return
            }
            startWhenPossible = false
            pipStartFallbackWorkItem?.cancel()
            pipStartFallbackWorkItem = nil
            possibleObservation?.invalidate()
            possibleObservation = nil
            pipController?.delegate = nil
            pipController = nil
        }
        
        private func installPipController(for playerLayer: AVPlayerLayer) {
            guard IS_CATALYST else { return }
            guard AVPictureInPictureController.isPictureInPictureSupported() else {
#if DEBUG
                L.og.debug("Native PiP: not supported on this device")
#endif
                return
            }
            guard playerLayer.player != nil else {
#if DEBUG
                L.og.debug("Native PiP: playerLayer has no player")
#endif
                return
            }
            
            invalidatePipControllerOnly()
            
            guard let pip = AVPictureInPictureController(playerLayer: playerLayer) else {
#if DEBUG
                L.og.debug("Native PiP: AVPictureInPictureController init failed")
#endif
                return
            }
            pip.delegate = self
            if #available(iOS 14.2, *) {
                pip.canStartPictureInPictureAutomaticallyFromInline = true
            }
            pipController = pip
            
            possibleObservation = pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
                guard let self else { return }
#if DEBUG
                L.og.debug("Native PiP: isPictureInPicturePossible=\(controller.isPictureInPicturePossible)")
#endif
                if controller.isPictureInPicturePossible, self.startWhenPossible, !controller.isPictureInPictureActive {
                    self.startWhenPossible = false
                    self.pipStartFallbackWorkItem?.cancel()
                    self.pipStartFallbackWorkItem = nil
#if DEBUG
                    L.og.debug("Native PiP: starting from KVO (now possible)")
#endif
                    controller.startPictureInPicture()
                }
            }
#if DEBUG
            L.og.debug("Native PiP: controller ready, possible=\(pip.isPictureInPicturePossible)")
#endif
        }
        
        @discardableResult
        func teardownNativePictureInPicture() -> Bool {
            pipTimelinePrimingGeneration += 1
            if isPrimingPipTimeline {
                isPrimingPipTimeline = false
                parent.player.currentItem?.cancelPendingSeeks()
            }
            if pictureInPictureState != .idle {
                isTearingDown = true
                stopNativePictureInPicture()
                // Keep the controller, its delegate, and source layer alive until AVKit sends
                // didStop. Detaching them here is what leaves Catalyst PiP orphaned.
                return false
            }
            finishNativePictureInPictureTeardown()
            return true
        }

        private func finishNativePictureInPictureTeardown() {
            invalidatePipControllerOnly()
            catalystPlayerLayerView?.playerLayer.player = nil
            catalystPlayerLayerView?.removeFromSuperview()
            catalystPlayerLayerView = nil
            isTearingDown = false
            Task { @MainActor in
                if AnyPlayerModel.shared.isNativePictureInPictureActive {
                    AnyPlayerModel.shared.isNativePictureInPictureActive = false
                }
            }
        }
        
        @discardableResult
        func startNativePictureInPicture() -> Bool {
            guard IS_CATALYST else { return false }
            guard !isPrimingPipTimeline else { return true }
            guard pictureInPictureState == .idle else {
                // Treat repeated clicks while start/stop is in flight as handled. In
                // particular, never replace the controller used by an outstanding start.
                return true
            }
            guard AVPictureInPictureController.isPictureInPictureSupported() else {
#if DEBUG
                L.og.debug("Native PiP start: not supported")
#endif
                return false
            }
            guard parent.viewMode != .audioOnlyBar else {
#if DEBUG
                L.og.debug("Native PiP start: blocked in audio-only mode")
#endif
                return false
            }
            
            // Reuse the surface prepared by make/leave-audio-only. Reattaching an
            // already-playing on-demand item immediately before every start makes Catalyst's
            // PiP chrome treat that attachment as time zero, even though AVPlayer playback
            // correctly continues at its current time.
            //
            // Audio-only transitions rebuild their surfaces at the transition boundary. Only
            // repair the surface here when it is actually missing or stale.
            if catalystPlayerLayerView?.playerLayer.player !== parent.player || pipController == nil {
                rebuildCatalystSurface(player: parent.player, reason: "startPiPRepair")
            }
            
            // Ensure playback intent is applied on the new layer.
            if parent.isPlaying, parent.player.timeControlStatus != .playing {
                if AnyPlayerModel.shared.isStream {
                    parent.player.playImmediately(atRate: 1.0)
                }
                else {
                    parent.player.play()
                }
            }
            
            guard let pip = pipController else {
#if DEBUG
                L.og.debug("Native PiP start: no controller after surface preparation")
#endif
                return false
            }
            
            // Catalyst can initially present an AVPlayerLayer-backed PiP timeline from 00:00
            // until the item emits its first seek/discontinuity update. Prime that transport
            // state once per on-demand item with a position-preserving seek, then start PiP.
            // This is the same update the system receives when the user taps ±10 seconds, but
            // without changing the video's actual playback position.
            if !AnyPlayerModel.shared.isStream,
               let item = parent.player.currentItem,
               pipTimelinePrimedItem !== item {
                let currentTime = parent.player.currentTime()
                if currentTime.isNumeric, currentTime > .zero {
                    isPrimingPipTimeline = true
                    pipTimelinePrimingGeneration += 1
                    let generation = pipTimelinePrimingGeneration
                    parent.player.seek(
                        to: currentTime,
                        toleranceBefore: .zero,
                        toleranceAfter: .zero
                    ) { [weak self, weak item] _ in
                        DispatchQueue.main.async {
                            guard let self, generation == self.pipTimelinePrimingGeneration else { return }
                            self.isPrimingPipTimeline = false
                            guard !self.isTearingDown,
                                  let item,
                                  item === self.parent.player.currentItem
                            else { return }
                            self.pipTimelinePrimedItem = item
                            self.startNativePictureInPicture()
                        }
                    }
                    return true
                }
            }

            if pip.isPictureInPictureActive {
                pictureInPictureState = .active
                return true
            }
            
            if pip.isPictureInPicturePossible {
#if DEBUG
                L.og.debug("Native PiP start: starting now")
#endif
                pictureInPictureState = .starting
                pip.startPictureInPicture()
                return true
            }
            
            // Wait for possible (KVO) + time-bounded fallback to custom overlay.
#if DEBUG
            L.og.debug("Native PiP start: waiting until possible")
#endif
            startWhenPossible = true
            pictureInPictureState = .starting
            pipStartFallbackWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.startWhenPossible else { return }
                self.startWhenPossible = false
                if self.pipController?.isPictureInPictureActive == true { return }
                self.pictureInPictureState = .idle
#if DEBUG
                L.og.debug("Native PiP start: timed out — falling back to overlay")
#endif
                Task { @MainActor in
                    guard AnyPlayerModel.shared.availableViewModes.contains(.overlay) else { return }
                    withAnimation {
                        AnyPlayerModel.shared.viewMode = .overlay
                    }
                }
            }
            pipStartFallbackWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
            return true
        }
        
        func stopNativePictureInPicture() {
            guard let pipController else { return }
            guard pictureInPictureState != .stopping else { return }
            guard pipController.isPictureInPictureActive else {
                // A stop can race with start. Keep the session intact; didStart will stop it.
                if pictureInPictureState == .starting {
                    pictureInPictureState = .stopping
                }
                return
            }
            pictureInPictureState = .stopping
            pipController.stopPictureInPicture()
        }
        
        /// After system PiP closes: restore inline surface and force-resume if still intended.
        private func restoreInlinePlaybackAfterPiP() {
            Task { @MainActor in
                AnyPlayerModel.shared.isNativePictureInPictureActive = false

                if self.isTearingDown {
                    self.finishNativePictureInPictureTeardown()
                    self.unregisterNativePiPHandlers()
                    return
                }
                
                if AnyPlayerModel.shared.isStream {
                    // Live HLS can leave the old layer unable to render after PiP. Its timeline
                    // is unbounded, so rebuilding the surface doesn't reset an elapsed-time UI.
                    self.rebuildCatalystSurface(player: self.parent.player, reason: "streamPipDidStop")
                }
                else {
                    // Preserve the exact layer/controller pair for on-demand video. A new
                    // AVPlayerLayer starts a new Catalyst PiP presentation timeline at zero,
                    // which makes the next PiP window show 00:00 despite correct AVPlayer time.
                    self.catalystPlayerLayerView?.isHidden = false
                    self.avpc?.view.isHidden = false
                    self.avpc?.view.setNeedsLayout()
                    self.avpc?.view.layoutIfNeeded()
                }
                
                // System PiP often leaves rate at 0 while our intent is still "playing".
                if AnyPlayerModel.shared.isPlaying, !AnyPlayerModel.shared.didFinishPlaying {
                    if AnyPlayerModel.shared.isStream {
                        AnyPlayerModel.shared.player.playImmediately(atRate: 1.0)
                    }
                    else {
                        AnyPlayerModel.shared.player.play()
                    }
                    // Second kick after layout — live HLS can stall on the first attempt after PiP.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        guard AnyPlayerModel.shared.isPlaying,
                              !AnyPlayerModel.shared.didFinishPlaying,
                              AnyPlayerModel.shared.player.timeControlStatus != .playing
                        else { return }
                        if AnyPlayerModel.shared.isStream {
                            AnyPlayerModel.shared.player.playImmediately(atRate: 1.0)
                        }
                        else {
                            AnyPlayerModel.shared.player.play()
                        }
                    }
                }
            }
        }

        /// The system's return-to-app control requests UI restoration before PiP stops. The
        /// X button stops PiP without that request and should close playback altogether.
        private func handleNativePictureInPictureDidStop() {
            if isTearingDown {
                restoreInlinePlaybackAfterPiP()
                return
            }

            if shouldRestoreInlineAfterPipStop {
                shouldRestoreInlineAfterPipStop = false
                restoreInlinePlaybackAfterPiP()
                return
            }

            Task { @MainActor in
                AnyPlayerModel.shared.close()
            }
        }
        
        @objc func respondToSwipeGesture(_ swipe: UISwipeGestureRecognizer) {
            Task { @MainActor in
                switch AnyPlayerModel.shared.viewMode {
                case .detailstream where AnyPlayerModel.shared.availableViewModes.contains(.overlay):
                    if IS_CATALYST {
                        AnyPlayerModel.shared.enterPictureInPicture()
                    }
                    else {
                        AnyPlayerModel.shared.viewMode = .overlay
                    }
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
            AppDelegate.supportedOrientations = .portrait
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
        
        // MARK: - AVPlayerViewControllerDelegate (system-driven PiP)
        
        func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            shouldRestoreInlineAfterPipStop = false
            Task { @MainActor in
                AnyPlayerModel.shared.isNativePictureInPictureActive = true
            }
        }
        
        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            handleNativePictureInPictureDidStop()
        }
        
        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            shouldRestoreInlineAfterPipStop = true
            Task { @MainActor in
                if !AnyPlayerModel.shared.isShown {
                    AnyPlayerModel.shared.isShown = true
                }
                AnyPlayerModel.shared.isNativePictureInPictureActive = false
                completionHandler(true)
            }
        }
        
        // MARK: - AVPictureInPictureControllerDelegate (programmatic PiP)
        
        func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
#if DEBUG
            L.og.debug("Native PiP did start")
#endif
            startWhenPossible = false
            pipStartFallbackWorkItem?.cancel()
            pipStartFallbackWorkItem = nil
            if pictureInPictureState == .stopping {
                pictureInPictureController.stopPictureInPicture()
                return
            }
            pictureInPictureState = .active
            shouldRestoreInlineAfterPipStop = false
            Task { @MainActor in
                AnyPlayerModel.shared.isNativePictureInPictureActive = true
            }
        }
        
        func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
#if DEBUG
            L.og.debug("Native PiP did stop")
#endif
            pictureInPictureState = .idle
            handleNativePictureInPictureDidStop()
        }
        
        func pictureInPictureController(
            _ pictureInPictureController: AVPictureInPictureController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            shouldRestoreInlineAfterPipStop = true
            Task { @MainActor in
                if !AnyPlayerModel.shared.isShown {
                    AnyPlayerModel.shared.isShown = true
                }
                AnyPlayerModel.shared.isNativePictureInPictureActive = false
                completionHandler(true)
            }
        }
        
        func pictureInPictureController(
            _ pictureInPictureController: AVPictureInPictureController,
            failedToStartPictureInPictureWithError error: Error
        ) {
#if DEBUG
            L.og.debug("Native PiP failed to start: \(error.localizedDescription)")
#endif
            startWhenPossible = false
            pipStartFallbackWorkItem?.cancel()
            pipStartFallbackWorkItem = nil
            pictureInPictureState = .idle
            Task { @MainActor in
                AnyPlayerModel.shared.isNativePictureInPictureActive = false
                if AnyPlayerModel.shared.availableViewModes.contains(.overlay) {
                    withAnimation {
                        AnyPlayerModel.shared.viewMode = .overlay
                    }
                }
            }
        }
    }
}
