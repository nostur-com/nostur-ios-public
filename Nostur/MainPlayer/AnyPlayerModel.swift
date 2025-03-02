//
//  AnyPlayer.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/01/2025.
//

import SwiftUI
import Combine
import AVKit

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
            else if viewMode == .fullscreen {
                UIApplication.shared.isIdleTimerDisabled = true
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
    @Published var cachedVideo: CachedVideo?
    @Published var isStream = false
    
    
    @Published var thumbnailUrl: URL? = nil
    
    public var availableViewModes: [AnyPlayerViewMode] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    public var currentlyPlayingUrl: String? = nil // when loading EmbeddedVideoView, check if we are currently playing the same already
    
    private init() {
        player.preventsDisplaySleepDuringVideoPlayback = false
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
        self.cachedVideo = nil
        self.thumbnailUrl = nrLiveEvent.thumbUrl
        
        if nrLiveEvent.streamHasEnded, let recordingUrl = nrLiveEvent.recordingUrl, let url = URL(string: recordingUrl) {
            isStream = false
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        }
        else if let url = nrLiveEvent.url {
            isStream = true
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        }

        // Don't reuse existing viewMode
        self.viewMode = availableViewModes.first ?? .detailstream
        isPlaying = true
    }
    
    // VIDEO URL
    @MainActor
    public func loadVideo(url: String, availableViewModes: [AnyPlayerViewMode] = [.fullscreen, .overlay], nrPost: NRPost? = nil) async {
        guard let url = URL(string: url) else { return }
        
        try? AVAudioSession.sharedInstance().setActive(true)
        sendNotification(.stopPlayingVideo)
        
        self.nrPost = nrPost
        self.didFinishPlaying = false
        self.isShown = true
        self.nrLiveEvent = nil
        self.aspect = 16/9 // reset
        self.availableViewModes = availableViewModes
        self.cachedVideo = nil

        
        self.isStream = url.absoluteString.suffix(4) == "m3u8" || url.absoluteString.suffix(3) == "m4a" || url.absoluteString.suffix(3) == "mp3"
        
        if isStream {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        }
        
        // If we already have cache, load video / dimensions / aspect from there
        else if let cachedVideo = AVAssetCache.shared.get(url: url.absoluteString) {
            self.cachedVideo = cachedVideo
            self.aspect = cachedVideo.dimensions.width / cachedVideo.dimensions.height
            player.replaceCurrentItem(with: AVPlayerItem(asset: cachedVideo.asset))
//            print("Video width: \(cachedVideo.dimensions.width), height: \(cachedVideo.dimensions.height)")
            self.currentlyPlayingUrl = url.absoluteString
        }
        else { // else we need to get it from .tracks etc
            let asset = AVAsset(url: url)
            guard let track = asset.tracks(withMediaType: .video).first else { return }
            let size = track.naturalSize.applying(track.preferredTransform)
            let dimensions = CGSize(width: abs(size.width), height: abs(size.height))
            
            if let duration = await getDuration(asset: asset) {
                let firstFrame = await getVideoFirstFrame(asset: asset)
                
                let cachedVideo = CachedVideo(url: url.absoluteString, asset: asset, dimensions: dimensions, scaledDimensions: dimensions, duration: duration, firstFrame: firstFrame)
                
                AVAssetCache.shared.set(url: url.absoluteString, asset: cachedVideo)
                
                self.aspect = dimensions.width / dimensions.height
                player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                self.cachedVideo = cachedVideo
                self.currentlyPlayingUrl = url.absoluteString
//                print("Video width: \(dimensions.width), height: \(dimensions.height), UIScreen.height: \(UIScreen.main.bounds.height)")
            }
        }
        
        // Reuse existing viewMode if already playing
        if !isPlaying || !availableViewModes.contains(viewMode) {
            self.viewMode = availableViewModes.first ?? .fullscreen
        }
        isPlaying = true
    }
    
    // CACHED VIDEO
    @MainActor
    public func loadVideo(cachedVideo: CachedVideo, availableViewModes: [AnyPlayerViewMode] = [.fullscreen, .overlay], nrPost: NRPost? = nil) {
        
        try? AVAudioSession.sharedInstance().setActive(true)
        sendNotification(.stopPlayingVideo)
        
        self.nrPost = nrPost
        self.didFinishPlaying = false
        self.isShown = true
        self.nrLiveEvent = nil
        self.aspect = cachedVideo.dimensions.width / cachedVideo.dimensions.height
        self.availableViewModes = availableViewModes
        self.cachedVideo = cachedVideo
        self.isStream = false
        
        player.replaceCurrentItem(with: AVPlayerItem(asset: cachedVideo.asset))
        self.currentlyPlayingUrl = cachedVideo.url

        // Reuse existing viewMode if already playing
        if !isPlaying || !availableViewModes.contains(viewMode) {
            self.viewMode = availableViewModes.first ?? .fullscreen
        }
        if (self.viewMode == .fullscreen) {
            isPlaying = true
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
        sendNotification(.stopPlayingVideo)
        self.player.pause()
        self.player.replaceCurrentItem(with: nil)
        self.nrLiveEvent = nil
        self.nrPost = nil
        self.cachedVideo = nil
        self.aspect = 16/9 // reset
        self.didFinishPlaying = false
        isPlaying = false
        isShown = false
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






