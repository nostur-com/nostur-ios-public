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
                   .frame(height: fullWidth ? 600 : 250)
                   .background(Color("LightGray").opacity(0.2))
            }
            else if videoShown {
                if let asset, let scaledDimensions, let videoLength = videoLength {
                    VideoViewurRepresentable(asset: asset, isPlaying: $isPlaying, isMuted: $isMuted)
                        .frame(width: scaledDimensions.width, height: scaledDimensions.height)
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
                    .frame(height: fullWidth ? 600 : 250)
                    .background(Color("LightGray").opacity(0.2))
                }
                else {
                    if videoState == .cancelled {
                        Text("Cancelled")
                            .centered()
                            .frame(height: fullWidth ? 600 : 250)
                            .background(Color("LightGray").opacity(0.2))
                    }
                    else if videoState == .error {
                        Label("Failed to load video", systemImage: "exclamationmark.triangle.fill")
                            .centered()
                            .frame(height: fullWidth ? 600 : 250)
                            .background(Color("LightGray").opacity(0.2))
                    }
                }
            }
            else if videoState == .initial {
                Text("Tap to load video", comment:"Button to load a video in a post")
                    .centered()
                    .frame(height: fullWidth ? 600 : 250)
                    .background(Color("LightGray").opacity(0.2))
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
                Task {
                    await loadVideo()
                }
            }
        }
        .onDisappear {
            self.task?.cancel()
        }
    }
    
    func loadVideo() async {
        task = ImageProcessing.shared.video.imageTask(with: url)
        
        if let task {
            videoState = .loading
            for await progress in task.progress {
                self.percent = Int(ceil(progress.fraction * 100))
            }
        }
        
        if let response = try? await task?.response {
            if let type = response.container.type, type.isVideo, let asset = response.container.userInfo[.videoAssetKey] as? AVAsset {
                self.asset = asset
                videoState = .ready
                Task {
                    if let videoSize = await getVideoDimensions(asset: asset), let videoLength = await getVideoLength(asset: asset) {
                        self.scaledDimensions = getScaledVideoDimensions(videoSize: videoSize, availableWidth: videoWidth, maxHeight: 600)
                        self.videoLength = videoLength
                    }
                    else {
                        videoState = .error
                    }
                }
            }
            else {
                videoState = .error
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
        
        let content1 = "one image: https://nostur.com/test1.mp4 dunno"
        
        let urlsFromContent = getImgUrlsFromContent(content1)
        
        NosturVideoViewur(url:urlsFromContent[0],  pubkey: "dunno", videoWidth: UIScreen.main.bounds.width, isFollowing: true)
            .previewDevice(PreviewDevice(rawValue: "iPhone 14"))
    }
}
