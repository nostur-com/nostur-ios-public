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
    @Published var showsPlaybackControls = false
    
    public var aspect: CGFloat = 16/9
    public var isPortrait: Bool {
        aspect < 1
    }
    
    @Published var viewMode: AnyPlayerViewMode = .overlay {
        didSet {
            showsPlaybackControls = viewMode != .overlay
        }
    }

    @Published var cachedVideo: CachedVideo?
    
    public var availableViewModes: [AnyPlayerViewMode] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() { }
    
    @MainActor
    public func loadVideo(url: String, availableViewModes: [AnyPlayerViewMode] = [.fullscreen, .overlay]) async {
        guard let url = URL(string: url) else { return }
        
        self.availableViewModes = availableViewModes
        self.cachedVideo = nil

        cancellables.forEach { $0.cancel() }
        
        // If we already have cache, load video / dimensions / aspect from there
        if let cachedVideo = AVAssetCache.shared.get(url: url.absoluteString) {
            self.cachedVideo = cachedVideo
            self.aspect = cachedVideo.dimensions.width / cachedVideo.dimensions.height
            player = AVPlayer(playerItem: AVPlayerItem(asset: cachedVideo.asset))
            print("Video width: \(cachedVideo.dimensions.width), height: \(cachedVideo.dimensions.height)")
        }
        else { // else we need to get it from .tracks etc
            let asset = AVAsset(url: url)
            guard let track = asset.tracks(withMediaType: .video).first else { return }
            let size = track.naturalSize.applying(track.preferredTransform)
            let dimensions = CGSize(width: abs(size.width), height: abs(size.height))
            
            if let videoLength = await getVideoLength(asset: asset) {
                let firstFrame = await getVideoFirstFrame(asset: asset)
                
                let cachedVideo = CachedVideo(url: url.absoluteString, asset: asset, dimensions: dimensions, scaledDimensions: dimensions, videoLength: videoLength, firstFrame: firstFrame)
                
                AVAssetCache.shared.set(url: url.absoluteString, asset: cachedVideo)
                
                self.aspect = dimensions.width / dimensions.height
                player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                self.cachedVideo = cachedVideo
                print("Video width: \(dimensions.width), height: \(dimensions.height)")
            }
        }
        
        // Observe the player's rate to determine if it's playing
        player.publisher(for: \.rate, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .map { $0 != 0 }
            .assign(to: \.isPlaying, on: self)
            .store(in: &cancellables)
        
        self.viewMode =  availableViewModes.first ?? .fullscreen
        if (self.viewMode == .fullscreen) {
            isPlaying = true
        }
    }
    
    public func loadVideo(cachedVideo: CachedVideo, availableViewModes: [AnyPlayerViewMode] = [.fullscreen, .overlay]) {
        
        self.aspect = cachedVideo.dimensions.width / cachedVideo.dimensions.height
        
        self.availableViewModes = availableViewModes
        self.cachedVideo = cachedVideo
        cancellables.forEach { $0.cancel() }
        player = AVPlayer(playerItem: AVPlayerItem(asset: cachedVideo.asset))
        
        // Observe the player's rate to determine if it's playing
        player.publisher(for: \.rate, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .map { $0 != 0 }
            .assign(to: \.isPlaying, on: self)
            .store(in: &cancellables)

        self.viewMode =  availableViewModes.first ?? .fullscreen
        if (self.viewMode == .fullscreen) {
            isPlaying = true
        }
    }
    
    @MainActor
    public func toggleViewMode() {
        if let index = availableViewModes.firstIndex(of: viewMode) {
            let nextIndex = (index + 1) % availableViewModes.count
            viewMode = availableViewModes[nextIndex]
        }
    }
    
    /// Starts video playback.
    func playVideo() {
        player.play()
    }
    
    /// Pauses video playback.
    func pauseVideo() {
        player.pause()
    }
    
    func seekForward() {
        let currentTime = player.currentTime()
        let newTime = CMTimeAdd(currentTime, CMTimeMake(value: 15, timescale: 1))
        player.seek(to: newTime)
    }
        
    func seekBackward() {
        let currentTime = player.currentTime()
        let newTime = CMTimeSubtract(currentTime, CMTimeMake(value: 15, timescale: 1))
        let clampedTime = CMTimeClampToRange(newTime, range: CMTimeRange(start: .zero, duration: player.currentItem?.duration ?? CMTime.indefinite))
        player.seek(to: clampedTime)
    }
    
    @MainActor
    public func close() {
        self.player.pause()
        self.cachedVideo = nil
        isPlaying = false
        cancellables.forEach { $0.cancel() }
    }
    
    deinit {
        cancellables.forEach { $0.cancel() }
    }
}

enum AnyPlayerViewMode {
    case overlay
    case detailstream
    case fullscreen
}






