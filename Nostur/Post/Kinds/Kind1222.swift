//
//  Kind1222.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/06/2025.
//

import SwiftUI
import AVFoundation
import CoreMedia
import Combine

// Kind 1222 and 1244
// 1222 for root messages and kind: 1244 for reply messages to be used for short voice messages, typically up to 60 seconds in length.
struct Kind1222: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.theme) private var theme: Theme
    @EnvironmentObject private var dim: DIMENSIONS
    @ObservedObject private var settings: SettingsStore = .shared
    private let nrPost: NRPost
    @ObservedObject private var pfpAttributes: PFPAttributes
    
    private let hideFooter: Bool // For rendering in NewReply
    private let missingReplyTo: Bool // For rendering in thread
    private var connect: ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    private let isReply: Bool // is reply on PostDetail
    private let isDetail: Bool
    private let isEmbedded: Bool
    private let fullWidth: Bool
    private let grouped: Bool
    private let forceAutoload: Bool
    
    private let THREAD_LINE_OFFSET = 24.0
    
    
    private var availableWidth: CGFloat {
        if isDetail || fullWidth || isEmbedded {
            return dim.listWidth - 20
        }
        
        return dim.availableNoteRowImageWidth()
    }
    
    private var isOlasGeneric: Bool { (nrPost.kind == 1 && (nrPost.kTag ?? "") == "20") }
    
    @State var localAudioFileURL: URL? = nil
    
    init(nrPost: NRPost, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, isReply: Bool = false, isDetail: Bool = false, isEmbedded: Bool = false, fullWidth: Bool, grouped: Bool = false, forceAutoload: Bool = false) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.isReply = isReply
        self.fullWidth = fullWidth
        self.isDetail = isDetail
        self.isEmbedded = isEmbedded
        self.grouped = grouped
        self.forceAutoload = forceAutoload
    }
    
    var body: some View {
        if nrPost.plainTextOnly {
            Text("TODO PLAINTEXTONLY") // TODO: PLAIN TEXTO ONLY
        }
        else if isEmbedded {
            self.embeddedView
        }
        else {
            self.normalView
        }
    }
    
    private var shouldAutoload: Bool {
        return !nrPost.isNSFW && (forceAutoload || SettingsStore.shouldAutodownload(nrPost) || nxViewingContext.contains(.screenshot))
    }
    
    @ViewBuilder
    private var normalView: some View {
//        #if DEBUG
//        let _ = Self._printChanges()
//        #endif
        PostLayout(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isReply: isReply, isDetail: isDetail, fullWidth: fullWidth || isOlasGeneric, forceAutoload: forceAutoload) { 
            if (isDetail) {
                if missingReplyTo || nxViewingContext.contains(.screenshot) {
                    ReplyingToFragmentView(nrPost: nrPost)
                }
                if let subject = nrPost.subject {
                    Text(subject)
                        .fontWeight(.bold)
                        .lineLimit(3)
                }
                if dim.listWidth < 75 { // Probably too many embeds in embeds in embeds in embeds, no space left
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                else {
                    self.audioView
                }
            }
            else {
                
                if missingReplyTo || nxViewingContext.contains(.screenshot) {
                    ReplyingToFragmentView(nrPost: nrPost)
                }
                if let subject = nrPost.subject {
                    Text(subject)
                        .fontWeight(.bold)
                        .lineLimit(3)
                }
                if dim.listWidth < 75 { // Probably too many embeds in embeds in embeds in embeds, no space left
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                else {
                    self.audioView
                }

            }
        }
    }
    
    @State var cancellable: AnyCancellable?
    
    @ViewBuilder
    private var audioView: some View {
        if let localAudioFileURL {
            VoiceMessagePlayer(fileURL: localAudioFileURL)
        }
        else {
            ProgressView()
                .onAppear {
                    guard let urlContent = nrPost.content, !urlContent.isEmpty, let url = URL(string: urlContent)
                    else { return }
                    
                    cancellable = DownloadManager.shared.publisher(for: url)
                        .sink { state in
                            if state.isDownloading {
                                print("Downloading…")
                            } else if let fileURL = state.fileURL {
                                print("✅ Downloaded to: \(fileURL.path)")
                                self.localAudioFileURL = fileURL
                            } else if let error = state.error {
                                print("❌ Error: \(error.localizedDescription)")
                            }
                        }
                    
                    DownloadManager.shared.startDownload(from: url)
                }
        }
    }
    
    @ViewBuilder
    private var embeddedView: some View {
        PostEmbeddedLayout(nrPost: nrPost) {
            
            if missingReplyTo || nxViewingContext.contains(.screenshot) {
                ReplyingToFragmentView(nrPost: nrPost)
            }
            if let subject = nrPost.subject {
                Text(subject)
                    .fontWeight(.bold)
                    .lineLimit(3)
            }
            if dim.listWidth < 75 { // Probably too many embeds in embeds in embeds in embeds, no space left
                Image(systemName: "exclamationmark.triangle.fill")
            }
            else {
                self.audioView
            }
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

struct VoiceMessagePlayer: View {
    @Environment(\.theme) private var theme
    let fileURL: URL
    var samples: [Int]?
    
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
    
    
    private func cleanup() {
        progressTimer?.invalidate()
        progressTimer = nil
        
        if isPlaying {
            player?.pause()
            isPlaying = false
        }
        
        audioObserver?.removeObservers()
        audioObserver = nil
        player = nil
        
//        // Clean up downloaded file
//        try? FileManager.default.removeItem(at: fileURL)
    }
    
    private func startProgressTimer() {
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
            Button { 
                if isPlaying {
                    player?.pause()
                    isPlaying = false
                } else {
                    if isFinished {
                        player?.seek(to: .zero)
                        isFinished = false
                    }
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
            }
            else {
                ProgressView()
            }
        }
        .frame(height: 50)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onAppear {
            Task {
                if let samples {
                    L.a1.debug("VoiceMessagePlayer.onAppear: samples: \(samples.count)")
                    self._samples = samples
                }
                else {
                    Task.detached(priority: .userInitiated) {
                        L.a1.debug("VoiceMessagePlayer.onAppear: loadAudioSamples(from: \(fileURL)")
                        let samples = (try? await loadAudioSamples(from: fileURL)) ?? []
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
                }
                
                do {
                    audioObserver = AudioPlayerObserver {
                        isPlaying = false
                        isFinished = true
                        progress = 1.0
                        progressTimer?.invalidate()
                        progressTimer = nil
                    }
                    
                    let playerItem = AVPlayerItem(url: fileURL)
                    player = AVPlayer(playerItem: playerItem)
                    L.a1.debug("VoiceMessagePlayer.onAppear: Trying to load: \(fileURL)")
                    
                    audioObserver?.addFinishObserver(to: player!)
                    
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
                    
                } catch {
                    errorMessage = "Failed to load audio: \(error.localizedDescription)"
                    L.a1.error("VoiceMessagePlayer.onAppear: Failed to load audio: \(error.localizedDescription)")
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


#Preview("Voice Message") {
    PreviewContainer({ pe in
        pe.parseMessages([
//            ###"["EVENT","voice",{"id":"3d89633c73db03ec49431e98a01f57d268f51d684d4f213a1f970fa3bb1b3714","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1747141170,"kind":1222,"tags":[],"content":"https://24242.io/1ca0ab176fa1259847f57b8bf93d38790e8797c7762762673b5aec46885140f9.webm","sig":"6785c8b32fcb9e03f02b25ccdbce211c43e74742b8f70f91b4629f323b56b16b8f1ab6a10421e97e5e37834fcc55e799370e62d78daffa56bf70ca1ab1b16fa1"}]"###
//            ###"["EVENT","voice",{"id":"3d89633c73db03ec49431e98a01f57d268f51d684d4f213a1f970fa3bb1b3714","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1747141170,"kind":1222,"tags":[],"content":"http://localhost:3000/f3290797cd055bc7417a4736e09b509abc9ba08d3558f1c48d9d348711512ec0.m4a","sig":"6785c8b32fcb9e03f02b25ccdbce211c43e74742b8f70f91b4629f323b56b16b8f1ab6a10421e97e5e37834fcc55e799370e62d78daffa56bf70ca1ab1b16fa1"}]"###
            ###"["EVENT","dit_is_een_test",{"id":"3d89633c73db03ec49431e98a01f57d268f51d684d4f213a1f970fa3bb1b3714","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1747141170,"kind":1222,"tags":[],"content":"http://localhost:3000/6d99ec56d05e444c048bedb88bd21c7636c36b2ac855aa9867b688ba4c994cb1.m4a","sig":"6785c8b32fcb9e03f02b25ccdbce211c43e74742b8f70f91b4629f323b56b16b8f1ab6a10421e97e5e37834fcc55e799370e62d78daffa56bf70ca1ab1b16fa1"}]"###,
            ###"["EVENT","fiatjaf",{"tags":[["p","cfb9b7be3ddecf3e787534aebfae23e66c4f8f76dc037dfee3ce9766fbeb1247"],["e","a196725e420b7bcb758e291833e745c34d7f5ff65eddad435dbbe07783348669"],["k","1222"],["P","cfb9b7be3ddecf3e787534aebfae23e66c4f8f76dc037dfee3ce9766fbeb1247"],["E","a196725e420b7bcb758e291833e745c34d7f5ff65eddad435dbbe07783348669"],["K","1222"]],"pubkey":"cfb9b7be3ddecf3e787534aebfae23e66c4f8f76dc037dfee3ce9766fbeb1247","content":"https://blossom.primal.net/2b80f037585b413ef48c433903153e6cc1cdd06890d1123e15e5df585870e07a.mp4","id":"96dd82763abe004512b0077233af307bd6cc55cae1dce87612b3e061fee99461","sig":"8a2c18d3dbc37a5483e05be05b085ccce03b3b49d1440d8a24903d2b29a356f94960ff7215de5730912bb65529541a76a4794fc5e9e4ed2b92b3509258bc8a3e","created_at":1752243807,"kind":1244}]"###
        ])
        pe.loadContacts()
        pe.loadPosts()
    }) {
        PreviewFeed {
            // 3d89633c73db03ec49431e98a01f57d268f51d684d4f213a1f970fa3bb1b3714
            // 96dd82763abe004512b0077233af307bd6cc55cae1dce87612b3e061fee99461
            if let voiceMessage = PreviewFetcher.fetchNRPost("3d89633c73db03ec49431e98a01f57d268f51d684d4f213a1f970fa3bb1b3714") {
                Box {
                    PostRowDeletable(nrPost: voiceMessage)
                }
            }
//            if let nrPost = PreviewFetcher.fetchNRPost() {
//                Box {
//                    PostRowDeletable(nrPost: nrPost)
//                }
//            }
//            if let article = PreviewFetcher.fetchNRPost("d3f509e5eb6dd06f96d4797969408f5f9c90e9237f012f83130b1fa592b26433") {
//                Box {
//                    PostRowDeletable(nrPost: article)
//                }
//            }
            Spacer()
        }
        .background(Themes.default.theme.listBackground)
    }
}
