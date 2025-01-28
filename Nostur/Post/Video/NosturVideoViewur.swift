//
//  NosturVideoViewur.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/05/2023.
//

import SwiftUI
import NukeUI
import Nuke
import NukeVideo
import AVFoundation

@MainActor
struct NosturVideoViewur: View {
    @Environment(\.openURL) private var openURL
    public let url: URL
    public let pubkey: String
    public var height: CGFloat?
    public let videoWidth: CGFloat
    public let autoload: Bool
    public var fullWidth: Bool = false
    public var contentPadding: CGFloat = 10.0
    public var theme: Theme
    @Binding public var didStart: Bool
    public var thumbnail: URL?
    
    @State private var videoState:VideoLoadingState = .initial
    @State private var videoShown = true
    @State private var cachedVideo:CachedVideo? = nil
    @State private var task:AsyncImageTask? = nil
    @State private var percent = 0
    @State private var loadNonHttpsAnyway = false
    @State private var isPlaying = false
    @State private var isMuted = false
    @State private var isStream = false
    
    static let aspect: CGFloat = 16/9
    
    var body: some View {
        VStack {
            if url.absoluteString.prefix(7) == "http://" && !loadNonHttpsAnyway {
                VStack {
                    Text("non-https media blocked", comment: "Displayed when an image in a post is blocked")
                    Button(String(localized: "Show anyway", comment: "Button to show the blocked content anyway")) {
                        loadNonHttpsAnyway = true
                        videoShown = true
                        Task {
                            await loadVideo()
                        }
                    }
                }
               .centered()
               .frame(width: videoWidth, height: (height ?? (videoWidth / Self.aspect)))
               .background(theme.lineColor.opacity(0.5))
            }
            else if isStream {
                if SettingsStore.shared.lowDataMode {
                    Text(url.absoluteString)
                        .foregroundColor(theme.accent)
                        .underline()
                        .onTapGesture {
                            openURL(url)
                        }
                        .padding(.horizontal, fullWidth ? 10 : 0)
                }
                else {
                    MusicOrVideo(url: url, isPlaying: $isPlaying, isMuted: $isMuted, didStart: $didStart, fullWidth: fullWidth, contentPadding: contentPadding, videoWidth: videoWidth, thumbnail: thumbnail)
                }
            }
            else if videoShown {
                if let scaledDimensionsFromCache = cachedVideo?.scaledDimensions,
                    let videoLength = cachedVideo?.videoLength {
                    let scaledDimensions = Nostur.scaledToFit(scaledDimensionsFromCache, scale: 1.0, maxWidth: videoWidth, maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                    theme.lineColor.opacity(0.5)
                        .frame(width: scaledDimensions.width, height: scaledDimensions.height)
                        .overlay {
                            if let firstFrame = cachedVideo?.firstFrame {
                                Image(uiImage: firstFrame)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: scaledDimensions.width, height: scaledDimensions.height)
                            }
                        }
                        .overlay(alignment: .center) {
                            if !didStart {
                                Button(action: {
                                    isPlaying = true
                                    didStart = true
                                    sendNotification(.startPlayingVideo, url.absoluteString)
                                    
                                    AnyPlayerModel
                                        .shared
                                        .loadVideo(
                                            url: "https://static.vecteezy.com/system/resources/previews/016/465/804/mp4/silhouettes-flock-of-seagulls-over-the-sea-during-amazing-sky-video.mp4",
            //                                availableViewModes: [.fullscreen, .overlay, .detailstream])
                                            availableViewModes: [.fullscreen, .overlay])
                                }) {
                                    Image(systemName:"play.circle")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 80, height: 80)
//                                        .centered()
                                        .contentShape(Rectangle())
//                                        .withoutAnimation()
                                }
                            }
                        }
                        .overlay(alignment: .bottomLeading) {
                            if !didStart {
                                Text(videoLength)
                                    .foregroundColor(.white)
                                    .fontWeight(.bold)
                                    .padding(3)
                                    .background(.black)
                                    .padding(5)
                            }
                        }
                        .overlay {
                            if didStart, let asset = cachedVideo?.asset {
                                VideoViewurRepresentable(url: url, asset: asset, isPlaying: $isPlaying, isMuted: $isMuted)
                                    .onReceive(receiveNotification(.startPlayingVideo)) { notification in
                                        let otherUrl = notification.object as! String
                                        if url.absoluteString != otherUrl {
                                            isPlaying = false
                                        }
                                    }
                                    .onDisappear {
                                        isPlaying = false
                                    }
                            }
                        }
//                    .withoutAnimation()
//                    .transaction { t in t.animation = nil }
#if DEBUG
//                    .opacity(0.25)
//                    .debugDimensions("videoShown")
#endif
                }
                else if SettingsStore.shared.lowDataMode {
                    Text(url.absoluteString)
                        .foregroundColor(theme.accent)
                        .underline()
                        .onTapGesture {
                            openURL(url)
                        }
                        .padding(.horizontal, fullWidth ? 10 : 0)
                }
                else if videoState == .loading {
                    HStack(spacing: 5) {
                        ProgressView()
                        Text(percent, format:.percent)
                            .frame(width: 48, alignment: .leading)
                        Image(systemName: "multiply.circle.fill")
                            .onTapGesture {
                                task?.cancel()
                                videoState = .cancelled
                            }
                    }
//                    .centered()
                    .frame(width: videoWidth, height: (height ?? (videoWidth / Self.aspect)))
                    .background(theme.lineColor.opacity(0.5))
                }
                else {
                    if videoState == .cancelled {
                        Text("Cancelled")
                            .centered()
                            .frame(width: videoWidth, height: (height ?? (videoWidth / Self.aspect)))
                            .background(theme.lineColor.opacity(0.2))
                    }
                    else if videoState == .error {
                        Label("Failed to load video", systemImage: "exclamationmark.triangle.fill")
                            .centered()
                            .frame(width: videoWidth, height: (height ?? (videoWidth / Self.aspect)))
                            .background(theme.lineColor.opacity(0.5))
                    }
                }
            }
            else if videoState == .initial {
                Text("Tap to load video", comment:"Button to load a video in a post")
                    .centered()
                    .frame(width: videoWidth, height: (height ?? (videoWidth / Self.aspect)))
                    .background(theme.lineColor.opacity(0.5))
                    .highPriorityGesture(
                        TapGesture()
                            .onEnded { _ in
                                videoShown = true
                                Task {
                                    await loadVideo()
                                }
                            }
                    )
            }
        }
        .onAppear {
            videoShown = !SettingsStore.shared.restrictAutoDownload || autoload
            if videoShown {
                if url.absoluteString.suffix(4) == "m3u8" || url.absoluteString.suffix(3) == "m4a" || url.absoluteString.suffix(3) == "mp3" {
                    isStream = true
                }
                else {
                    if let cachedVideo = AVAssetCache.shared.get(url: url.absoluteString) {
                        self.cachedVideo = cachedVideo
                    }
                    else {
                        guard !SettingsStore.shared.lowDataMode else { return }
                        Task.detached(priority: .background) {
                            await loadVideo()
                        }
                    }
                }
            }
        }
        .onDisappear {
            self.task?.cancel()
        }
//        .transaction { t in t.animation = nil }
    }
    
    private func loadVideo() async {
        task = ImageProcessing.shared.video.imageTask(with: url)
        
        if let task {
            DispatchQueue.main.async {
                videoState = .loading
            }
            for await progress in task.progress {
                let percent = Int(ceil(progress.fraction * 100))
                if percent % 3 == 0 { // only update view every 3 percent for performance
                    DispatchQueue.main.async {
                        self.percent = percent
                    }
                }
            }
        }
        
        if let response = try? await task?.response {
            if let type = response.container.type, type.isVideo, let asset = response.container.userInfo[.videoAssetKey] as? AVAsset {
                Task.detached(priority: .background) {
                    if let videoSize = await getVideoDimensions(asset: asset), let videoLength = await getVideoLength(asset: asset) {
                        
                        let scaledDimensions = Nostur.scaledToFit(videoSize, scale: 1, maxWidth: videoWidth, maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                        let firstFrame = await getVideoFirstFrame(asset: asset)
                        
                        let cachedVideo = CachedVideo(asset: asset, scaledDimensions: scaledDimensions, videoLength: videoLength, firstFrame: firstFrame)
                        AVAssetCache.shared.set(url: url.absoluteString, asset: cachedVideo)
                        
                        DispatchQueue.main.async {
                            self.cachedVideo = cachedVideo
                            videoState = .ready
                        }
                    }
                    else {
                        DispatchQueue.main.async {
                            videoState = .error
                        }
                    }
                }
            }
            else {
                DispatchQueue.main.async {
                    videoState = .error
                }
            }
        }
    }
    
    private enum VideoLoadingState {
        case initial
        case loading
        case ready
        case error
        case cancelled
    }
}



struct NosturVideoViewur_Previews: PreviewProvider {
    static var previews: some View {
        
        // Use ImageDecoderRegistory to add the decoder to the
        let _ = ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
        
        let content1 = "one image: https://cdn.stemstr.app/stream/87b5962ef9e37845c72ae0fa2748e8e5b1b257274e8e2e0a8cdd5d3b5e5ff596.m3u8 dunno"
//        let content1 = "one image: https://nostur.com/test1.mp4 dunno"
        
        let urlsFromContent = getImgUrlsFromContent(content1)
        
        NosturVideoViewur(url:urlsFromContent[0],  pubkey: "dunno", videoWidth: UIScreen.main.bounds.width, autoload: true, theme: Themes.default.theme, didStart: .constant(false))
            .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}

class AVAssetCache {
    static let shared = AVAssetCache()
    
    private var cache:NSCache<NSString, CachedVideo>

    private init() {
        self.cache = NSCache<NSString, CachedVideo>()
        self.cache.countLimit = 5
    }

    public func get(url:String) -> CachedVideo? {
        return cache.object(forKey: url as NSString)
    }
    
    public func set(url:String, asset:CachedVideo) {
        cache.setObject(asset, forKey: url as NSString)
    }
}

class CachedVideo {
    let asset:AVAsset
    var scaledDimensions:CGSize? = nil
    var videoLength:String? = nil
    var firstFrame:UIImage? = nil
    
    init(asset: AVAsset, scaledDimensions: CGSize? = nil, videoLength: String? = nil, firstFrame: UIImage? = nil) {
        self.asset = asset
        self.scaledDimensions = scaledDimensions
        self.videoLength = videoLength
        self.firstFrame = firstFrame
    }
}
