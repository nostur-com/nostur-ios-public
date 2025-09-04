//
//  VoiceMessagePlayer.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/07/2025.
//

import SwiftUI
import AVFoundation
import CoreMedia
import Combine

struct VoiceMessagePlayer: View {
    @Environment(\.theme) private var theme
    var url: URL // Remote audio file url
    var samples: [Int]?
    
    
    @State private var cancellable: AnyCancellable?
    @State private var localFileURL: URL? // downloaded file url
    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = false
    @State private var audioObserver: AudioPlayerObserver?
    @State private var errorMessage: String?
    @State private var progress: Double = 0.0
    @State private var isFinished: Bool = false
    @State private var progressTimer: Timer? = nil
    @State private var isScrubbing: Bool = false
    @State private var duration: TimeInterval = 0
    
    @State private var _samples: [Int]?
    @State private var forceDownload: Bool = false
    
    private func convertWebmToM4a(webmURL: URL) async -> URL? {
        guard webmURL.pathExtension.lowercased() == "webm" else {
            return webmURL // Not a webm file, just return original
        }
        
        // Create output URL with .m4a extension
        let outputURL = webmURL.deletingPathExtension().appendingPathExtension("m4a")
        
        // Check if converted file already exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
#if DEBUG
            L.a0.debug("VoiceMessagePlayer: Converted file already exists: \(outputURL.path)")
#endif
            return outputURL
        }
        
#if DEBUG
        L.a0.debug("VoiceMessagePlayer: Converting \(webmURL.path) to \(outputURL.path)")
#endif
        
        let result = convert_webm_to_m4a(webmURL.path, outputURL.path)

        if result == 0 && FileManager.default.fileExists(atPath: outputURL.path) {
#if DEBUG
            L.a0.debug("VoiceMessagePlayer: ✅ Conversion successful: \(outputURL.path)")
#endif
            return outputURL
        } else {
#if DEBUG
            L.a0.debug("VoiceMessagePlayer: ❌ Conversion failed with code: \(result)")
#endif
            return nil
        }
    }
    
    private func cleanup() {
        progressTimer?.invalidate()
        progressTimer = nil
        
        if isPlaying {
            player?.pause()
        }
        isPlaying = false
        
        audioObserver?.removeObservers()
        audioObserver = nil
        player = nil
    }
    
    private func startProgressTimer() {
        guard progressTimer == nil else { return }
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard let p = player, !isScrubbing, duration > 0 else { return }
            let currentTime = CMTimeGetSeconds(p.currentTime())
            if duration > 0 {
                progress = currentTime / duration
            }
            if p.timeControlStatus != .playing {
                isPlaying = false
                progressTimer?.invalidate()
                progressTimer = nil
            }
        }
    }
    
    var body: some View {
        HStack {
            if let localFileURL {
                Button {
                    if isPlaying {
                        player?.pause()
                        isPlaying = false
                    } else {
                        if isFinished {
                            player?.seek(to: .zero)
                            isFinished = false
                        }
                        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
                        try? AVAudioSession.sharedInstance().setActive(true)
                        player?.play()
                        isPlaying = true
                        startProgressTimer()
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(theme.accent)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(player == nil)
                .onAppear {
                    Task.detached(priority: .userInitiated) {
                        // Convert webm to m4a if needed
                        let processedFileURL: URL
                        if let convertedURL = await convertWebmToM4a(webmURL: localFileURL) {
                            processedFileURL = convertedURL
                            // Update localFileURL to point to the converted file
                            Task { @MainActor in
                                self.localFileURL = convertedURL
                            }
                        } else {
                            processedFileURL = localFileURL
                        }
                        
                        if await _samples == nil {
#if DEBUG
                            L.a0.debug("VoiceMessagePlayer.onAppear: loadAudioSamples(from: \(processedFileURL))")
#endif
                            let samples = (try? await loadAudioSamples(from: processedFileURL)) ?? []
                            Task { @MainActor in
                                self._samples = samples
                                print(samples.map {
                                    if $0 == 0 {
                                        return "0"
                                    }
                                    return String($0)
                                }.joined(separator: " "))
                            }
                        }
                        
                        Task { @MainActor in
                            audioObserver = AudioPlayerObserver {
                                isPlaying = false
                                isFinished = true
                                progress = 1.0
                                progressTimer?.invalidate()
                                progressTimer = nil
                            }
                        }

                        let playerItem: AVPlayerItem
                        
                        if processedFileURL.pathExtension.isEmpty { // AVPlayer doesn't play files without extension, so just try appending .m4a and it works.
                            
                            
                            // For files without extension, create a copy with guessed extension
                            let tempURL = switch detectAudioFormat(processedFileURL) {
                            case .opus:
                                processedFileURL.appendingPathExtension("opus")
                            case .flac:
                                processedFileURL.appendingPathExtension("flac")
                            case .mobile3GPP:
                                processedFileURL.appendingPathExtension("3gp")
                            default:
                                processedFileURL.appendingPathExtension("m4a")
                            }
                            
                            // Try to create a symbolic link or copy the file with the correct extension
                            do {
                                // Remove any existing temp file
                                try? FileManager.default.removeItem(at: tempURL)
                                
                                // Try creating a hard link first (most efficient)
                                do {
                                    try FileManager.default.linkItem(at: processedFileURL, to: tempURL)
                                    playerItem = AVPlayerItem(url: tempURL)
#if DEBUG
                                    L.a0.debug("VoiceMessagePlayer: Created hard link for extensionless file")
#endif
                                } catch {
                                    // If hard link fails, try copying the file
                                    try FileManager.default.copyItem(at: processedFileURL, to: tempURL)
                                    playerItem = AVPlayerItem(url: tempURL)
#if DEBUG
                                    L.a0.debug("VoiceMessagePlayer: Copied file with .m4a extension")
#endif
                                }
                            } catch {
                                // If all else fails, try the original approach
#if DEBUG
                                L.a0.debug("VoiceMessagePlayer: Failed to create temp file, using original: \(error)")
#endif
                                playerItem = AVPlayerItem(url: processedFileURL)
                            }
                        } else {
                            // File has extension, use directly
                            playerItem = AVPlayerItem(url: processedFileURL)
                        }
                        
                        Task { @MainActor in
                            player = AVPlayer(playerItem: playerItem)
#if DEBUG
                            L.a0.debug("VoiceMessagePlayer.onAppear: Trying to load: \(processedFileURL)")
#endif
                            audioObserver?.addFinishObserver(to: player!)
                        }
                        
                        // Observe when player item finishes
                        NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: playerItem,
                            queue: .main
                        ) { _ in
                            isPlaying = false
                            isFinished = true
                            progress = 1.0
                            progressTimer?.invalidate()
                            progressTimer = nil
                        }
                        
                        // Get duration when ready
                        Task {
                            while playerItem.status != .readyToPlay {
                                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                            }
                            
                            let durationSeconds = CMTimeGetSeconds(playerItem.duration)
                            if durationSeconds.isFinite && durationSeconds > 0 {
                                await MainActor.run {
                                    self.duration = durationSeconds
                                }
                            }
                        }
                        
                        if await forceDownload {
                            Task { @MainActor in
                                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
                                try? AVAudioSession.sharedInstance().setActive(true)
                                player?.play()
                                isPlaying = true
                                startProgressTimer()
                            }
                        }
                    }
                }
                
            }
            else {
                if SettingsStore.shared.lowDataMode && !forceDownload {
                    Button {
                        forceDownload = true
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(theme.accent)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                else {
                    Button {
                        
                    } label: {
                        ProgressView()
                            .tint(Color.white)
                            .frame(width: 50, height: 50)
                            .background(theme.accent)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onAppear {
                        // if url is a local file url
                        if url.isFileURL {
                            localFileURL = url
                        }
                        else {
                            
                            cancellable = DownloadManager.shared.publisher(for: url, subFolder: "a0")
                                .sink { state in
                                    if state.isDownloading {
#if DEBUG
                                        L.a0.debug("Downloading: \(url)")
#endif
                                    } else if let fileURL = state.fileURL {
#if DEBUG
                                        L.a0.debug("✅ Downloaded to: \(fileURL.path)")
#endif
                                        self.localFileURL = fileURL
                                    } else if let error = state.error {
#if DEBUG
                                        L.a0.debug("❌ Error: \(error.localizedDescription)")
#endif
                                    }
                                }
                            
                            DownloadManager.shared.startDownload(from: url, subFolder: "a0")
                        }
                    }
                }
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage).foregroundColor(.red)
            }
            else if let _samples {
                WaveformView(samples: _samples, progress: $progress, onScrub: { newProgress in
                    guard let p = player, duration > 0 else { return }
                    let seekTime = CMTime(seconds: newProgress * duration, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                    p.seek(to: seekTime)
                    if isFinished && newProgress < 1.0 {
                        isFinished = false
                    }
                }, duration: duration, isPlaying: isPlaying)
                .frame(maxHeight: .infinity)
                .allowsHitTesting(localFileURL != nil)
            }
            else {
                if SettingsStore.shared.lowDataMode && !forceDownload {
                    Spacer()
                }
                else {
                    ProgressView()
                }
            }
        }
        .frame(height: 50)
        .padding(.vertical, 4)
        .onAppear {
            Task {
                if let samples {
#if DEBUG
                    L.a0.debug("VoiceMessagePlayer.onAppear: samples: \(samples.count)")
#endif
                    self._samples = samples
                }
            }
        }
        .onDisappear {
            cleanup()
        }
        .onChange(of: progress) { newValue in
            guard let p = player, duration > 0, isScrubbing else { return }
            if isFinished && newValue < 1.0 {
                isFinished = false
            }
            let seekTime = CMTime(seconds: newValue * duration, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            p.seek(to: seekTime)
        }
    }
}

class AudioPlayerObserver: NSObject {
    var onFinish: () -> Void
    
    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        super.init()
    }
    
    func addFinishObserver(to player: AVPlayer) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
    }
    
    @objc private func playerDidFinishPlaying() {
        onFinish()
    }
    
    func removeObservers() {
        NotificationCenter.default.removeObserver(self)
    }
    
    deinit {
        removeObservers()
    }
}

func detectAudioFormat(_ url: URL) -> CMFormatDescription.MediaSubType? {
    guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }
    return audioFile.fileFormat.formatDescription.mediaSubType
}
