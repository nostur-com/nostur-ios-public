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
import MediaPlayer

class AnyPlayerModel: ObservableObject {
    
    static let shared = AnyPlayerModel()
    
    // MARK: - State Variables
    @Published var player = AVPlayer()
    @Published var isPlaying = false
    @Published var didFinishPlaying = false // to show Like/Zap
    @Published var showsPlaybackControls = false
    @Published var timeControlStatus: AVPlayer.TimeControlStatus = .paused
    
    @Published var isLoading = false
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
        setupRemoteControl()
        player.preventsDisplaySleepDuringVideoPlayback = true
        player.actionAtItemEnd = .pause
        
        player.publisher(for: \.rate, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .map { $0 != 0 }
            .assign(to: \.isPlaying, on: self)
            .store(in: &cancellables)
        
        player
            .publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStatus in
                self?.timeControlStatus = newStatus
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] _ in
                self?.didFinishPlaying = true
            }
            .store(in: &cancellables)
    }
    
    // LIVE EVENT STREAM
    @MainActor
    public func loadLiveEvent(nrLiveEvent: NRLiveEvent, availableViewModes: [AnyPlayerViewMode] = [.detailstream, .overlay, .fullscreen, .audioOnlyBar], nrPost: NRPost? = nil) async {
        
        // View updates
        sendNotification(.stopPlayingVideo)
        self.nrPost = nil
        self.didFinishPlaying = false
        self.isLoading = true
        self.isShown = true
        self.nrLiveEvent = nrLiveEvent
        self.aspect = 16/9 // reset
        self.availableViewModes = availableViewModes
        self.cachedFirstFrame = nil
        self.thumbnailUrl = nrLiveEvent.thumbUrl
        // Don't reuse existing viewMode
        self.viewMode = availableViewModes.first ?? .detailstream
        playVideo()
        
        if nrLiveEvent.streamHasEnded, let recordingUrl = nrLiveEvent.recordingUrl, let url = URL(string: recordingUrl) {
            isStream = false
            self.currentlyPlayingUrl = url.absoluteString
            
            Task.detached(priority: .userInitiated) {
                let playerItem = AVPlayerItem(url: url)
                Task { @MainActor in
                    self.player.replaceCurrentItem(with: playerItem)
                    self.isLoading = false
                }
            }
            
        }
        else if let url = nrLiveEvent.url {
            isStream = true
            self.currentlyPlayingUrl = url.absoluteString
            Task.detached(priority: .userInitiated) {
                let playerItem = AVPlayerItem(url: url)
                Task { @MainActor in
                    self.player.replaceCurrentItem(with: playerItem)
                    self.isLoading = false
                }
            }
        }
        
        Task {
            await setupNowPlayingInfo(artist: nrPost?.anyName, title: nrLiveEvent.title, mediaType: .anyVideo, thumbUrl: nrLiveEvent.thumbUrl, pfpUrl: nrPost?.contact.pictureUrl, isLive: !nrLiveEvent.streamHasEnded)
        }
    }
    
    // VIDEO URL
    @MainActor
    public func loadVideo(url: String, availableViewModes: [AnyPlayerViewMode] = [.fullscreen, .overlay, .audioOnlyBar], nrPost: NRPost? = nil, cachedFirstFrame: CachedFirstFrame? = nil) async {
        guard let url = URL(string: url) else { return }
        
        // View updates
        sendNotification(.stopPlayingVideo)
        self.nrPost = nrPost
        self.didFinishPlaying = false
        self.isLoading = true
        self.nrLiveEvent = nil
        self.aspect = 16/9 // reset
        self.availableViewModes = availableViewModes
        self.isStream = url.absoluteString.suffix(4) == "m3u8" || url.absoluteString.suffix(3) == "m4a" || url.absoluteString.suffix(3) == "mp3"
        self.currentlyPlayingUrl = url.absoluteString
        
        self.viewMode = availableViewModes.first ?? .fullscreen
        self.isShown = true
        
        
        // Avoid hangs, do rest here
        Task.detached(priority: .medium) {
            self.cachedFirstFrame = cachedFirstFrame
            
            if self.isStream {
                let playerItem = AVPlayerItem(url: url)
                Task { @MainActor in
                    self.player.replaceCurrentItem(with: playerItem)
                    self.playVideo()
                    self.setupRemoteControl()
                    self.isLoading = false
                }
            }
            else {
                
                if let cachedFirstFrame {
                    if let dimensions = cachedFirstFrame.dimensions {
                        Task { @MainActor in
                            self.aspect = dimensions.width / dimensions.height
                        }
                    }
                }
                
                if url.host?.contains("twimg.com") == true { // Add playback hack for twitter videos. Download first instead of stream
                    // Create a URLRequest with proper headers
                    var request = URLRequest(url: url)
                    request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
                    request.setValue("*/*", forHTTPHeaderField: "Accept")
                    request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
                    request.setValue("https://twitter.com", forHTTPHeaderField: "Origin")
                    request.setValue("https://twitter.com/", forHTTPHeaderField: "Referer")
                    
                    do {
                        let (data, response) = try await URLSession.shared.data(for: request)
                        
                        guard let httpResponse = response as? HTTPURLResponse,
                              httpResponse.statusCode == 200 else {
#if DEBUG
                                L.og.debug("Failed to fetch video: \(response)")
#endif
                            return
                        }
                        
                        // Create a temporary file to store the video data
                        let tempDir = FileManager.default.temporaryDirectory
                        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".mp4")
                        try data.write(to: tempFile)
                        
                        // Create AVPlayerItem from the local file
                        let playerItem = AVPlayerItem(url: tempFile)
                        
                        // Clean up the temporary file when the player item is done
                        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { _ in
                            try? FileManager.default.removeItem(at: tempFile)
                        }
                        
                        // TODO: maybe clean up all .mp4 if observer didn't catch it or others
                        
                        if cachedFirstFrame == nil {
                            let asset = AVAsset(url: tempFile)
                            guard let track = asset.tracks(withMediaType: .video).first else { return }
                            let size = track.naturalSize.applying(track.preferredTransform)
                            let dimensions = CGSize(width: abs(size.width), height: abs(size.height))
                            Task { @MainActor in
                                self.aspect = dimensions.width / dimensions.height
                            }
                        }
                        
                        Task { @MainActor in
                            self.player.replaceCurrentItem(with: playerItem)
                            self.playVideo()
                            self.setupRemoteControl()
                            self.isLoading = false
                        }
                    } catch {
#if DEBUG
                        L.og.debug("Error loading video: \(error)")
#endif
                        Task { @MainActor in
                            self.isLoading = false
                        }
                    }
                }
                else { // Normal video stream
                    let asset = AVAsset(url: url)
                    if cachedFirstFrame == nil {
                        guard let track = asset.tracks(withMediaType: .video).first else { return }
                        let size = track.naturalSize.applying(track.preferredTransform)
                        let dimensions = CGSize(width: abs(size.width), height: abs(size.height))
                        Task { @MainActor in
                            self.aspect = dimensions.width / dimensions.height
                        }
                    }
                    let playerItem = await AVPlayerItem(asset: asset)
                    Task { @MainActor in
                        self.player.replaceCurrentItem(with: playerItem)
                        self.playVideo()
                        self.setupRemoteControl()
                        self.isLoading = false
                    }
                }
            }
        }
        
        Task {
            await setupNowPlayingInfo(artist: nrPost?.anyName, mediaType: .anyVideo, duration: cachedFirstFrame?.duration?.seconds, pfpUrl: nrPost?.contact.pictureUrl, thumb: cachedFirstFrame?.uiImage )
        }
    }
    
    func setupRemoteControl() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
       
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.changePlaybackRateCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.ratingCommand.isEnabled = false
        commandCenter.likeCommand.isEnabled = false
        commandCenter.dislikeCommand.isEnabled = false
        commandCenter.bookmarkCommand.isEnabled = false
        commandCenter.changeRepeatModeCommand.isEnabled = false
        commandCenter.changeShuffleModeCommand.isEnabled = false
        
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)


        commandCenter.playCommand.addTarget { (_) -> MPRemoteCommandHandlerStatus in
            self.isPlaying = true
            return .success
        }
        

        commandCenter.pauseCommand.addTarget { (_) -> MPRemoteCommandHandlerStatus in
            self.isPlaying = false
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { (_) -> MPRemoteCommandHandlerStatus in
            self.isPlaying = !self.isPlaying
            return .success
        }
      }
    
    func setupNowPlayingInfo(artist: String? = nil, title: String? = nil, mediaType: MPMediaType = .anyVideo, duration: TimeInterval? = nil, thumbUrl: URL? = nil, pfpUrl: URL? = nil, thumb: UIImage? = nil, isLive: Bool = false) async {
            
  
            
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyMediaType: NSNumber(value: mediaType.rawValue),
            MPNowPlayingInfoPropertyIsLiveStream: NSNumber(value: isLive),
        ]
        
        if let artist {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }
        
        if let title {
            nowPlayingInfo[MPMediaItemPropertyTitle] = title
        }
        
        if let duration {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }
        
        if let thumb {
            let mediaArtwork = MPMediaItemArtwork(boundsSize: thumb.size) { (size: CGSize) -> UIImage in
                return thumb
            }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = mediaArtwork
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            
        if thumb == nil {
            if let thumbUrl, let thumbUIImage: UIImage = await getNowPlayingThumb(thumbUrl, usePFPpipeline: false) {
                let mediaArtwork = MPMediaItemArtwork(boundsSize: thumbUIImage.size) { (size: CGSize) -> UIImage in
                    return thumbUIImage
                }
                nowPlayingInfo[MPMediaItemPropertyArtwork] = mediaArtwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            }
            else if let pfpUrl, let thumbUIImage: UIImage = await getNowPlayingThumb(pfpUrl, usePFPpipeline: true) {
                let mediaArtwork = MPMediaItemArtwork(boundsSize: thumbUIImage.size) { (size: CGSize) -> UIImage in
                    return thumbUIImage
                }
                nowPlayingInfo[MPMediaItemPropertyArtwork] = mediaArtwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            }
        }
    }
    
    @MainActor
    public func toggleViewMode() {
        let viewModes = viewMode == .audioOnlyBar ? availableViewModes : availableViewModes.filter({ $0 != .audioOnlyBar }) // never include audio bar in rotation
        if let index = viewModes.firstIndex(of: viewMode) {
            let nextIndex = (index + 1) % viewModes.count
            viewMode = viewModes[nextIndex]
            
            if viewMode == .detailstream {
                LiveKitVoiceSession.shared.objectWillChange.send() // Force update
            }
        }
    }
    
    @MainActor
    func playVideo() {
        isPlaying = true
        // Must be .playAndRecord. Now Playing control center doesn't work with just .playback https://developer.apple.com/forums/thread/674696
        // Also .mixWithOthers doesn't work with Now Player control center
        try? AVAudioSession.sharedInstance().setActive(false)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        
        // Only works when called after setting up audio session??
        UIApplication.shared.beginReceivingRemoteControlEvents()
        
        // Prevent auto-lock while playing
        UIApplication.shared.isIdleTimerDisabled = true
#if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .playing
#endif
    }
    
    @MainActor
    func pauseVideo() {
        isPlaying = false
#if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .paused
#endif
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
        self.playVideo()
        self.setupRemoteControl()
    }
    
    @MainActor
    public func close() {
        if let currentlyPlayingUrl {
            sendNotification(.didEndPIP, (currentlyPlayingUrl, self.cachedFirstFrame))
        }
        
        // Pause first to stop any ongoing playback
        self.player.pause()
        
        // Set flags to indicate we're closing
        isPlaying = false
        isShown = false
        isLoading = false
        
        // Clean up properties
        self.currentlyPlayingUrl = nil
        self.nrLiveEvent = nil
        self.nrPost = nil
        self.aspect = 16/9 // reset
        self.didFinishPlaying = false
        
        // Delay the player item replacement to allow AVPlayerViewController to clean up properly
        Task {
            // Small delay to ensure UI updates are processed
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            await MainActor.run {
                self.player.replaceCurrentItem(with: nil)
            }
        }
        
#if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
#endif
        // Restore normal idle behavior
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    public var downloadTask: ImageTask? // "Save to library" task
    public var nowPlayingThumbTask: ImageTask?
    
//    private var task: AsyncImageTask?
    
    public func getNowPlayingThumb(_ url: URL, usePFPpipeline: Bool = false) async -> UIImage? {
        if SettingsStore.shared.lowDataMode || url.absoluteString.prefix(7) == "http://" { return nil }
  
        self.nowPlayingThumbTask = usePFPpipeline
            ? ImageProcessing.shared.pfp.imageTask(with: pfpImageRequestFor(url))
            : ImageProcessing.shared.content.imageTask(with: makeImageRequest(url, label: "getNowPlayingThumb"))
        
        guard let task = self.nowPlayingThumbTask else {
            return nil
        }
        
        do {
            let response = try await task.response
            if response.container.type == .gif {
                return nil
            }
            else {
                return response.image
            }
        }
        catch {
           return nil
        }
    }
    
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
        // Cancel all Combine cancellables first
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        
        // Clean up player and its item to avoid KVO issues
        player.pause()
        player.replaceCurrentItem(with: nil)
        
        // Cancel any ongoing tasks
        downloadTask?.cancel()
        nowPlayingThumbTask?.cancel()
        
        // Clean up remote control
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
    }
}

enum AnyPlayerViewMode {
    case overlay
    case detailstream
    case fullscreen
    case audioOnlyBar
}
