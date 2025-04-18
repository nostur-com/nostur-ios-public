//
//  AnyPlayer.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/01/2025.
//

import SwiftUI
import Combine
import AVKit
import NukeUI
import Nuke
import NukeVideo

class AnyPlayerModel: ObservableObject {
    
    static let shared = AnyPlayerModel()
    
    // MARK: - State Variables
    @Published var player = AVPlayer()
    @Published var isPlaying = false
    @Published var didFinishPlaying = false // to show Like/Zap
    @Published var showsPlaybackControls = false
    
    @Published var isShown = false
    
    public var aspect: CGFloat = 16/9
    public var isPortrait: Bool {
        aspect < 1
    }
    
    @Published var viewMode: AnyPlayerViewMode = .overlay {
        didSet {
            showsPlaybackControls = viewMode != .overlay
            if viewMode == .detailstream {
                LiveKitVoiceSession.shared.objectWillChange.send() // Force update
            }
        }
    }

    @Published var nrLiveEvent: NRLiveEvent? {
        didSet {
            if nrLiveEvent == nil {
                LiveKitVoiceSession.shared.visibleNest = nil
            }
        }
    }
    @Published var nrPost: NRPost? = nil
    @Published var isStream = false
    
    
    @Published var thumbnailUrl: URL? = nil
    
    public var availableViewModes: [AnyPlayerViewMode] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    public var currentlyPlayingUrl: String? = nil // when loading EmbeddedVideoView, check if we are currently playing the same already
    public var cachedFirstFrame: CachedFirstFrame? = nil // to restore .playingInPIP view back to first frame
    
    private init() {
        player.preventsDisplaySleepDuringVideoPlayback = true
        player.actionAtItemEnd = .pause
        
        player.publisher(for: \.rate, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .map { $0 != 0 }
            .assign(to: \.isPlaying, on: self)
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [self] _ in
                didFinishPlaying = true
            }
            .store(in: &cancellables)
    }
    
    // LIVE EVENT STREAM
    @MainActor
    public func loadLiveEvent(nrLiveEvent: NRLiveEvent, availableViewModes: [AnyPlayerViewMode] = [.detailstream, .overlay, .fullscreen], nrPost: NRPost? = nil) async {
        
        try? AVAudioSession.sharedInstance().setActive(true)
        sendNotification(.stopPlayingVideo)
        
        self.nrPost = nil
        self.didFinishPlaying = false
        self.isShown = true
        self.nrLiveEvent = nrLiveEvent
        self.availableViewModes = availableViewModes
        self.cachedFirstFrame = nil
        self.thumbnailUrl = nrLiveEvent.thumbUrl
        
        if nrLiveEvent.streamHasEnded, let recordingUrl = nrLiveEvent.recordingUrl, let url = URL(string: recordingUrl) {
            isStream = false
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            self.currentlyPlayingUrl = url.absoluteString
        }
        else if let url = nrLiveEvent.url {
            isStream = true
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            self.currentlyPlayingUrl = url.absoluteString
        }

        // Don't reuse existing viewMode
        self.viewMode = availableViewModes.first ?? .detailstream
        isPlaying = true
    }
    
    // VIDEO URL
    @MainActor
    public func loadVideo(url: String, availableViewModes: [AnyPlayerViewMode] = [.fullscreen, .overlay], nrPost: NRPost? = nil, cachedFirstFrame: CachedFirstFrame? = nil) async {
        guard let url = URL(string: url) else { return }
        
        // View updates
        sendNotification(.stopPlayingVideo)
        self.nrPost = nrPost
        self.didFinishPlaying = false
        self.isShown = true
        self.nrLiveEvent = nil
        self.aspect = 16/9 // reset
        self.availableViewModes = availableViewModes
        self.isStream = url.absoluteString.suffix(4) == "m3u8" || url.absoluteString.suffix(3) == "m4a" || url.absoluteString.suffix(3) == "mp3"
        self.currentlyPlayingUrl = url.absoluteString
        
        // Reuse existing viewMode if already playing, unless viewMode is not available
        if !self.isShown || !availableViewModes.contains(viewMode) {
            self.viewMode = availableViewModes.first ?? .fullscreen
        }
        isPlaying = true
        
        
        // Avoid hangs, do rest here
        Task.detached(priority: .medium) {
            self.cachedFirstFrame = cachedFirstFrame
            try? AVAudioSession.sharedInstance().setActive(true)
            
            if self.isStream {
                self.player.replaceCurrentItem(with: AVPlayerItem(url: url))
            }
            else {
                
                if let cachedFirstFrame {
                    if let dimensions = cachedFirstFrame.dimensions {
                        Task { @MainActor in
                            self.aspect = dimensions.width / dimensions.height
                        }
                    }
                }
                
                let asset = AVAsset(url: url)
                if cachedFirstFrame == nil {
                    guard let track = asset.tracks(withMediaType: .video).first else { return }
                    let size = track.naturalSize.applying(track.preferredTransform)
                    let dimensions = CGSize(width: abs(size.width), height: abs(size.height))
                    Task { @MainActor in
                        self.aspect = dimensions.width / dimensions.height
                    }
                }
                await self.player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
            }
        }
    }
    
    @MainActor
    public func toggleViewMode() {
        if let index = availableViewModes.firstIndex(of: viewMode) {
            let nextIndex = (index + 1) % availableViewModes.count
            viewMode = availableViewModes[nextIndex]
            
            if viewMode == .detailstream {
                LiveKitVoiceSession.shared.objectWillChange.send() // Force update
            }
        }
    }
    
    @MainActor
    func playVideo() {
        configureAudioSession()
        isPlaying = true
        player.play()
        try? AVAudioSession.sharedInstance().setActive(true)
        // Prevent auto-lock while playing
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    @MainActor
    func pauseVideo() {
        isPlaying = false
        player.pause()
    }
    
    @MainActor
    func seekForward() {
        let currentTime = player.currentTime()
        let newTime = CMTimeAdd(currentTime, CMTimeMake(value: 15, timescale: 1))
        player.seek(to: newTime)
    }
        
    @MainActor
    func seekBackward() {
        let currentTime = player.currentTime()
        let newTime = CMTimeSubtract(currentTime, CMTimeMake(value: 15, timescale: 1))
        let clampedTime = CMTimeClampToRange(newTime, range: CMTimeRange(start: .zero, duration: player.currentItem?.duration ?? CMTime.indefinite))
        player.seek(to: clampedTime)
        didFinishPlaying = false
    }
    
    @MainActor
    func replay() {
        didFinishPlaying = false
        player.seek(to: .zero)
        isPlaying = true
    }
    
    @MainActor
    public func close() {
        if let currentlyPlayingUrl {
            sendNotification(.didEndPIP, (currentlyPlayingUrl, self.cachedFirstFrame))
        }
        self.currentlyPlayingUrl = nil
        self.player.pause()
        self.player.replaceCurrentItem(with: nil)
        self.nrLiveEvent = nil
        self.nrPost = nil
        self.aspect = 16/9 // reset
        self.didFinishPlaying = false
        isPlaying = false
        isShown = false
        // Restore normal idle behavior
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    public var downloadTask: AsyncImageTask?
    
    @Published var downloadProgress: Int = 0
    
    // Needed for "Save to library"
    public func downloadVideo() async -> AVAsset? {
        guard let currentlyPlayingUrl, let videoUrl = URL(string: currentlyPlayingUrl) else { return nil }
        self.downloadTask = ImageProcessing.shared.video.imageTask(with: videoUrl)
        
        guard let downloadTask = self.downloadTask else { return nil }
        
        for await progress in downloadTask.progress {
            Task { @MainActor in
                let progress = Int(ceil(progress.fraction * 100))
                if progress != 100 { // don't show 100, because at 100 still needs a few seconds to save to library
                    self.downloadProgress = progress
                }
            }
        }
        
        if let response = try? await downloadTask.response {
            if let type = response.container.type, type.isVideo, let asset = response.container.userInfo[.videoAssetKey] as? AVAsset {
                return asset
            }
            else {
                return nil
            }
        }
        
        return nil
    }
    
    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
}

enum AnyPlayerViewMode {
    case overlay
    case detailstream
    case fullscreen
}

func configureAudioSession() {
    do {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
    } catch {
        L.og.error("Failed to configure audio session: \(error.localizedDescription)")
    }
}
