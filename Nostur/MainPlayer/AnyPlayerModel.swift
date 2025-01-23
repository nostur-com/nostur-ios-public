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
    
    // MARK: - State Variables
    @Published var player = AVPlayer(url: URL(string: "https://www.w3schools.com/html/mov_bbb.mp4")!)
    @Published var isPlaying = false
    @Published var showsPlaybackControls = false
//    @Published var showPlayer = true
    
    static let shared = AnyPlayerModel()
    
    @Published var viewMode: AnyPlayerViewMode = .overlay {
        didSet {
            showsPlaybackControls = viewMode != .overlay
        }
    }
    @Published var url: URL?
    
    public var availableViewModes: [AnyPlayerViewMode] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() { }
    
    @MainActor
    public func loadVideo(url: String, availableViewModes: [AnyPlayerViewMode] = [.fullscreen, .overlay]) {
        print("loadVideo \(url)")
        guard let url = URL(string: url) else { return }
        self.availableViewModes = availableViewModes
        if url != self.url {
            self.url = url
            cancellables.forEach { $0.cancel() }
            player = AVPlayer(url: url)
            
            // Observe the player's rate to determine if it's playing
            player.publisher(for: \.rate, options: [.initial, .new])
                .receive(on: DispatchQueue.main)
                .map { $0 != 0 }
                .assign(to: \.isPlaying, on: self)
                .store(in: &cancellables)
            
            // Alternatively, observe timeControlStatus for more detailed control (iOS 10+)
            /*
            player?.publisher(for: \.timeControlStatus, options: [.initial, .new])
                .receive(on: DispatchQueue.main)
                .map { $0 == .playing }
                .assign(to: \.isPlaying, on: self)
                .store(in: &cancellables)
            */
        }
        self.viewMode =  availableViewModes.first ?? .fullscreen
        if (self.viewMode == .fullscreen) {
            isPlaying = true
        }
    }
    
    @MainActor
    public func toggleViewMode() {
        print("toggleViewMode: available \(availableViewModes.count)")
        if let index = availableViewModes.firstIndex(of: viewMode) {
            let nextIndex = (index + 1) % availableViewModes.count
            viewMode = availableViewModes[nextIndex]
            print("toggleViewMode: available \(availableViewModes.count) current: \(index) next: \(nextIndex)")
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
    
    deinit {
        cancellables.forEach { $0.cancel() }
    }
}

enum AnyPlayerViewMode {
    case overlay
    case detailstream
    case fullscreen
}






