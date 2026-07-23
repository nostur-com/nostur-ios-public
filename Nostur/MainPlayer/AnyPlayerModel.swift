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
    /// System Picture in Picture is active (Mac Catalyst). Host stays mounted but chrome is hidden.
    @Published var isNativePictureInPictureActive = false
    
    public var aspect: CGFloat = 16/9
    public var isPortrait: Bool {
        aspect < 1
    }
    
    /// Wired by `AVPlayerViewControllerRepresentable` while the player host is mounted.
    var startNativePictureInPictureHandler: (() -> Bool)?
    var stopNativePictureInPictureHandler: (() -> Void)?
    
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
    private var playerItemReadinessCancellables = Set<AnyCancellable>()
#if DEBUG
    private var playbackItemDebugCancellables = Set<AnyCancellable>()
    private var playbackDebugStartedAt = Date()
#endif
    
    public var currentlyPlayingUrl: String? = nil // when loading EmbeddedVideoView, check if we are currently playing the same already
    public var cachedFirstFrame: CachedFirstFrame? = nil // to restore .playingInPIP view back to first frame
    
    private init() {
        setupRemoteControl()
        player.preventsDisplaySleepDuringVideoPlayback = true
        player.actionAtItemEnd = .pause
        setupPlayerItemReadiness()
#if DEBUG
        setupPlaybackDebugging()
#endif
        
        // IMPORTANT: do NOT assign `rate != 0` → isPlaying.
        // While buffering (esp. live HLS on device reopen), rate stays 0 for several seconds.
        // The old assign flipped isPlaying to false, then AVPlayerViewControllerRepresentable
        // saw !isPlaying && status == .waitingToPlay… and called pause(), killing startup.
        // Fullscreen "fixed" it by forcing a fresh updateUIView + play once the item was ready.
        // isPlaying is playback *intent*, set by playVideo/pauseVideo only (plus rate>0 confirm).
        player.publisher(for: \.rate, options: [.new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rate in
                guard let self, rate != 0 else { return }
                if !self.isPlaying {
                    self.isPlaying = true
                }
            }
            .store(in: &cancellables)
        
        player
            .publisher(for: \.timeControlStatus, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStatus in
                guard let self else { return }
                self.timeControlStatus = newStatus
#if DEBUG
                self.playbackDebugLog("timeControl=\(self.debugTimeControlStatus(newStatus)) rate=\(self.player.rate)")
#endif
                // Do not call play() again while waiting. Every repeated request makes AVPlayer
                // restart its buffering-rate evaluation and can prevent live HLS from starting.
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self, !self.didFinishPlaying else { return }
                if let ended = notification.object as? AVPlayerItem,
                   ended !== self.player.currentItem {
                    return
                }
                self.didFinishPlaying = true
                self.isPlaying = false
            }
            .store(in: &cancellables)
    }

    private func setupPlayerItemReadiness() {
        player.publisher(for: \.currentItem, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                guard let self else { return }
                self.playerItemReadinessCancellables.removeAll()
                guard let item else { return }

                item.publisher(for: \.status, options: [.initial, .new])
                    .receive(on: DispatchQueue.main)
                    .filter { $0 == .readyToPlay }
                    .prefix(1)
                    .sink { [weak self, weak item] _ in
                        guard let self, item === self.player.currentItem else { return }
                        guard self.isPlaying, !self.didFinishPlaying,
                              self.player.timeControlStatus != .playing else { return }
#if DEBUG
                        self.playbackDebugLog("item became ready; resuming intended playback once")
#endif
                        if self.isStream {
                            self.player.playImmediately(atRate: 1.0)
                        }
                        else {
                            self.player.play()
                        }
                    }
                    .store(in: &self.playerItemReadinessCancellables)
            }
            .store(in: &cancellables)
    }
    
    // LIVE EVENT STREAM
    @MainActor
    public func loadLiveEvent(nrLiveEvent: NRLiveEvent, availableViewModes: [AnyPlayerViewMode] = [.detailstream, .overlay, .fullscreen, .audioOnlyBar], nrPost: NRPost? = nil) async {
#if DEBUG
        playbackDebugStartedAt = Date()
        playbackDebugLog("loadLiveEvent mode=\(availableViewModes.first ?? .detailstream) ended=\(nrLiveEvent.streamHasEnded)")
#endif
        
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
        
        if nrLiveEvent.streamHasEnded, let recordingUrl = nrLiveEvent.recordingUrl, let url = URL(string: recordingUrl) {
            isStream = false
            self.currentlyPlayingUrl = url.absoluteString
            
            Task.detached(priority: .userInitiated) {
                let playerItem = AVPlayerItem(url: url)
                Task { @MainActor in
                    // Mount the view first so AVPC exists, then play (device needs the layer attached).
                    self.player.replaceCurrentItem(with: playerItem)
                    self.setupRemoteControl()
                    self.isLoading = false
                    self.playVideo()
                }
            }
            
        }
        else if let url = nrLiveEvent.url {
            isStream = true
            player.automaticallyWaitsToMinimizeStalling = false
            self.currentlyPlayingUrl = url.absoluteString
            Task.detached(priority: .userInitiated) {
                let playerItem = AVPlayerItem(url: url)
                Task { @MainActor in
                    self.player.replaceCurrentItem(with: playerItem)
                    self.setupRemoteControl()
                    self.isLoading = false
                    self.playVideo()
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
                    self.setupRemoteControl()
                    self.isLoading = false
                    self.playVideo()
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
                            self.setupRemoteControl()
                            self.isLoading = false
                            self.playVideo()
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
                        self.setupRemoteControl()
                        self.isLoading = false
                        self.playVideo()
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
    
    /// Prefer native system PiP on Mac; custom `.overlay` everywhere else (and as Mac fallback).
    @MainActor
    public func enterPictureInPicture() {
        if IS_CATALYST {
            let started = startNativePictureInPictureHandler?() ?? false
            if started {
                return
            }
#if DEBUG
            L.og.debug("Native PiP start unavailable — falling back to overlay")
#endif
        }
        guard availableViewModes.contains(.overlay) else { return }
        withAnimation {
            viewMode = .overlay
        }
    }
    
    @MainActor
    func playVideo() {
        let shouldRestartFromBeginning = didFinishPlaying || isAtEndOfCurrentItem
        didFinishPlaying = false
        isPlaying = true
        configurePlaybackSession()
        
        if shouldRestartFromBeginning {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
#if DEBUG
        playbackDebugLog("play() requested itemStatus=\(debugItemStatus(player.currentItem?.status)) playerStatus=\(debugPlayerStatus(player.status))")
#endif
        if isStream {
            player.automaticallyWaitsToMinimizeStalling = false
            player.playImmediately(atRate: 1.0)
        }
        else {
            player.automaticallyWaitsToMinimizeStalling = true
            player.play()
        }
#if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .playing
#endif
    }
    
    private var isAtEndOfCurrentItem: Bool {
        guard let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0 else { return false }
        let currentTime = player.currentTime().seconds
        guard currentTime.isFinite else { return false }
        return currentTime >= duration - 0.05
    }
    
    @MainActor
    private func configurePlaybackSession() {
        // Always re-apply .playback without .mixWithOthers (app launch uses mixWithOthers).
        // Avoid setActive(false) first — that can stall the next play on device after reopen.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
        
        UIApplication.shared.beginReceivingRemoteControlEvents()
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    @MainActor
    func pauseVideo() {
#if DEBUG
        playbackDebugLog("pause() requested")
#endif
        isPlaying = false
        player.pause()
#if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .paused
#endif
    }
    
    @MainActor
    func seekForward() {
        let currentTime = player.currentTime()
        let newTime = CMTimeAdd(currentTime, CMTimeMake(value: 10, timescale: 1))
        player.seek(to: newTime)
    }
        
    @MainActor
    func seekBackward() {
        let currentTime = player.currentTime()
        let newTime = CMTimeSubtract(currentTime, CMTimeMake(value: 10, timescale: 1))
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
#if DEBUG
        playbackDebugLog("close()")
#endif
        stopNativePictureInPictureHandler?()
        isNativePictureInPictureActive = false
        
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
        
        // Delay the player item replacement to allow AVPlayerViewController to clean up properly.
        // Skip if a new stream was opened in the meantime.
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            await MainActor.run {
                guard !self.isShown else { return }
                self.player.replaceCurrentItem(with: nil)
            }
        }
        
#if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
#endif
        // Restore normal idle behavior
        UIApplication.shared.isIdleTimerDisabled = false
    }

#if DEBUG
    private func setupPlaybackDebugging() {
        player.publisher(for: \.currentItem, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                guard let self else { return }
                self.playbackItemDebugCancellables.removeAll()
                guard let item else {
                    self.playbackDebugLog("currentItem=nil")
                    return
                }

                self.playbackDebugLog("currentItem attached status=\(self.debugItemStatus(item.status))")
                item.publisher(for: \.status, options: [.initial, .new])
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self, weak item] status in
                        guard let self else { return }
                        let error = item?.error?.localizedDescription ?? "none"
                        self.playbackDebugLog("itemStatus=\(self.debugItemStatus(status)) error=\(error)")
                    }
                    .store(in: &self.playbackItemDebugCancellables)

                NotificationCenter.default.publisher(for: .AVPlayerItemPlaybackStalled, object: item)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in self?.playbackDebugLog("playback stalled") }
                    .store(in: &self.playbackItemDebugCancellables)

                NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] notification in
                        let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                        self?.playbackDebugLog("failed to play: \(error?.localizedDescription ?? "unknown error")")
                    }
                    .store(in: &self.playbackItemDebugCancellables)

                NotificationCenter.default.publisher(for: .AVPlayerItemNewAccessLogEntry, object: item)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self, weak item] _ in
                        guard let event = item?.accessLog()?.events.last else { return }
                        self?.playbackDebugLog("accessLog bitrate=\(Int(event.observedBitrate)) indicated=\(Int(event.indicatedBitrate)) stalls=\(event.numberOfStalls) transfer=\(String(format: "%.2f", event.transferDuration))s")
                    }
                    .store(in: &self.playbackItemDebugCancellables)
            }
            .store(in: &cancellables)

        player.publisher(for: \.reasonForWaitingToPlay, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reason in
                self?.playbackDebugLog("waitingReason=\(reason?.rawValue ?? "none")")
            }
            .store(in: &cancellables)
    }

    private func playbackDebugLog(_ message: String) {
        let elapsed = Date().timeIntervalSince(playbackDebugStartedAt)
        L.og.debug("🎬 Player +\(String(format: "%.3f", elapsed))s \(message)")
    }

    private func debugItemStatus(_ status: AVPlayerItem.Status?) -> String {
        switch status {
        case .unknown: "unknown"
        case .readyToPlay: "readyToPlay"
        case .failed: "failed"
        case nil: "nil"
        @unknown default: "unknown-future"
        }
    }

    private func debugPlayerStatus(_ status: AVPlayer.Status) -> String {
        switch status {
        case .unknown: "unknown"
        case .readyToPlay: "readyToPlay"
        case .failed: "failed"
        @unknown default: "unknown-future"
        }
    }

    private func debugTimeControlStatus(_ status: AVPlayer.TimeControlStatus) -> String {
        switch status {
        case .paused: "paused"
        case .waitingToPlayAtSpecifiedRate: "waiting"
        case .playing: "playing"
        @unknown default: "unknown-future"
        }
    }
#endif
    
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
