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
    @EnvironmentObject var theme:Theme
    let url:URL
    let pubkey:String
    var height:CGFloat?
    let videoWidth:CGFloat
    let isFollowing:Bool
    var fullWidth:Bool = false
    var contentPadding:CGFloat = 10.0
    @State var videoState:VideoLoadingState = .initial
    @State var videoShown = true
    @State var asset:AVAsset? = nil
    @State var scaledDimensions:CGSize? = nil
    @State var videoLength:String? = nil
    @State var task:AsyncImageTask? = nil
    @State var percent = 0
    @State var loadNonHttpsAnyway = false
    @State var isPlaying = false
    @State var isMuted = false
    @State var didStart = false
    @State var isStream = false
    
    static let aspect:CGFloat = 16/9
    
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
               .background(theme.lineColor.opacity(0.2))
            }
            else if isStream {
                MusicStreamurRepresentable(url: url, isPlaying: $isPlaying, isMuted: $isMuted)
                    .frame(height: 75.0)
                    .padding(.horizontal, fullWidth ? -contentPadding : 0)
                    .overlay {
                        if !didStart {
                            Color.black
                                .overlay {
                                    Button(action: {
                                        isPlaying = true
                                        didStart = true
                                        sendNotification(.startPlayingVideo, url.absoluteString)
                                    }) {
                                        Image(systemName:"play.circle")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 45, height: 45)
                                            .centered()
                                            .contentShape(Rectangle())
                                    }
                                }
                        }
                    }
                    .overlay(alignment:.topTrailing) {
                        Image(systemName: "music.note")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .padding(3)
                            .background(.black)
                            .padding(5)
                    }
                    .onAppear {
                        isMuted = false
                    }
                    .onReceive(receiveNotification(.startPlayingVideo)) { notification in
                        let otherUrl = notification.object as! String
                        if url.absoluteString != otherUrl {
                            isPlaying = false
                            isMuted = true
                        }
                    }
//                    .onDisappear {
////                        isPlaying = false
////                        isMuted = true
//                    }
            }
            else if videoShown {
                if let asset, let scaledDimensions, let videoLength = videoLength {
                    VideoViewurRepresentable(asset: asset, isPlaying: $isPlaying, isMuted: $isMuted)
                        .padding(.horizontal, fullWidth ? -contentPadding : 0)
                        .overlay(alignment:.bottomLeading) {
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
                            if !didStart {
                                Button(action: {
                                    isPlaying = true
                                    didStart = true
                                    sendNotification(.startPlayingVideo, url.absoluteString)
                                }) {
                                    Image(systemName:"play.circle")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 80, height: 80)
                                        .centered()
                                        .contentShape(Rectangle())
                                }
                            }
                        }
                        .onReceive(receiveNotification(.startPlayingVideo)) { notification in
                            let otherUrl = notification.object as! String
                            if url.absoluteString != otherUrl {
                                isPlaying = false
                            }
                        }
                        .onDisappear {
                            isPlaying = false
                        }
                    .frame(width: scaledDimensions.width, height: scaledDimensions.height)
                    .transaction { t in t.animation = nil }
#if DEBUG
//                    .opacity(0.25)
//                    .debugDimensions("videoShown")
#endif
                }
                else if videoState == .loading {
                    HStack(spacing: 5) {
                        ProgressView()
                        Text(percent, format:.percent)
                        Image(systemName: "multiply.circle.fill")
                            .onTapGesture {
                                task?.cancel()
                                videoState = .cancelled
                            }
                    }
                    .centered()
                    .frame(width: videoWidth, height: (height ?? (videoWidth / Self.aspect)))
                    .background(theme.lineColor.opacity(0.2))
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
                            .background(theme.lineColor.opacity(0.2))
                    }
                }
            }
            else if videoState == .initial {
                Text("Tap to load video", comment:"Button to load a video in a post")
                    .centered()
                    .frame(width: videoWidth, height: (height ?? (videoWidth / Self.aspect)))
                    .background(theme.lineColor.opacity(0.2))
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
            videoShown = !SettingsStore.shared.restrictAutoDownload || isFollowing
            if videoShown {
                if url.absoluteString.suffix(4) == "m3u8" || url.absoluteString.suffix(3) == "m4a" {
                    isStream = true
                }
                else {
                    Task.detached {
                        await loadVideo()
                    }
                }
            }
        }
        .onDisappear {
            self.task?.cancel()
        }
        .transaction { t in t.animation = nil }
    }
    
    func loadVideo() async {
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
                Task.detached {
                    if let videoSize = await getVideoDimensions(asset: asset), let videoLength = await getVideoLength(asset: asset) {
                        DispatchQueue.main.async {
                            self.scaledDimensions = Nostur.scaledToFit(videoSize, scale: 1, maxWidth: videoWidth, maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                            self.videoLength = videoLength
                        }
                    }
                    else {
                        DispatchQueue.main.async {
                            videoState = .error
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.asset = asset
                        videoState = .ready
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
}

enum VideoLoadingState {
    case initial
    case loading
    case ready
    case error
    case cancelled
}

struct NosturVideoViewur_Previews: PreviewProvider {
    static var previews: some View {
        
        // Use ImageDecoderRegistory to add the decoder to the
        let _ = ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
        
        let content1 = "one image: https://cdn.stemstr.app/stream/87b5962ef9e37845c72ae0fa2748e8e5b1b257274e8e2e0a8cdd5d3b5e5ff596.m3u8 dunno"
//        let content1 = "one image: https://nostur.com/test1.mp4 dunno"
        
        let urlsFromContent = getImgUrlsFromContent(content1)
        
        NosturVideoViewur(url:urlsFromContent[0],  pubkey: "dunno", videoWidth: UIScreen.main.bounds.width, isFollowing: true)
            .previewDevice(PreviewDevice(rawValue: "iPhone 14"))
    }
}
