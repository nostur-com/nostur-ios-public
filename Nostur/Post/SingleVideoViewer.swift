//
//  SingleVideoViewer.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/05/2023.
//

import SwiftUI
import NukeUI
import Nuke
import NukeVideo
import AVFoundation

struct SingleVideoViewer: View {
    
    @EnvironmentObject var ns:NosturState // Only needed for `imagesShown`
    let url:URL
    let pubkey:String
    var height:CGFloat?
    let videoWidth:CGFloat
    let isFollowing:Bool
    var fullWidth:Bool = false
    @State var videoShown = false
    @State var isPlaying = false
    @State var asset:AVAsset? = nil
    @State var videoSize:CGSize? = nil
    @State var task:AsyncImageTask? = nil
//    @State var task:ImageTask? = nil
    @State var isLoading = false
    @State var percent = 0
    @State var didLoad = false
    @State var autoplay = false
    @State var cancelled = false
    
    
    var body: some View {
        VStack {
            if videoShown {
                if let asset, let videoSize {
                    let scaledWidth = videoWidth / videoSize.width
                    let scaledHeight = videoSize.height * scaledWidth
                    
                    VPV(asset: asset, isPlaying: $isPlaying)
                        .onTapGesture {
                            isPlaying.toggle()
                        }
                        .frame(height: scaledHeight)
                        .background(.regularMaterial)
                        .onDisappear { isPlaying = false }
                        .background(Color.black)
                        .overlay(
                            Button(action: {
                                if isPlaying {
                                    isPlaying = false
                                } else {
                                    sendNotification(.startPlayingVideo, url.absoluteString)
                                    isPlaying = true
                                }
                            }) {
                                Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 75, height: 75)
//                                                        .padding(80)
                            }.opacity(isPlaying ? 0 : 1)
                        )
                        .onReceive(receiveNotification(.startPlayingVideo)) { notification in
                            let otherUrl = notification.object as! String
                            if url.absoluteString != otherUrl {
                                isPlaying = false
                            }
                        }
                        .onAppear {
                            if autoplay { // Appear after loading = start auto playing because user tapped to load (play)..
                                isPlaying = true
                            }
                        }
                }
                else if isLoading && !didLoad {
                    HStack(spacing: 5) {
                        ProgressView()
                        Text("\(percent)%")
                        Image(systemName: "multiply.circle.fill")
                            .onTapGesture {
                                task?.cancel()
                                cancelled = true
                            }
                    }
                        .centered()
                }
                else {
                    if cancelled {
                        Text("Cancelled")
                            .centered()
                    }
                    else if !isLoading {
                        Label("Failed to load video", systemImage: "exclamationmark.triangle.fill")
                            .centered()
                    }
                }
            }
            else {
                Text("Tap to load video")
                    .centered()
                .frame(height: 250)
                .background(.regularMaterial)
                .onTapGesture {
                    videoShown = true
                    autoplay = true
                    Task {
                        await loadVideo()
                    }
                }
            }
        }
        .frame(minHeight: 250)
        .background(Color("LightGray"))
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
            isLoading = true
            for await progress in task.progress {
                self.percent = Int(ceil(progress.fraction * 100))
            }
            isLoading = false
            didLoad = true
        }
        
        
        if let response = try? await task?.response {
            if let type = response.container.type, type.isVideo, let asset = response.container.userInfo[.videoAssetKey] as? AVAsset {
                self.asset = asset
                Task {
                    if let videoSize = await getVideoDimensions(asset: asset) {
                        self.videoSize = videoSize
                    }
                }
            }
        }
        
        
//        let imageTask = ImagePipeline.shared.imageTask(with: url)
//
//           imageView.image = try await imageTask.image
//
//        { result in
//
////        task = ImageProcessing.shared.video.loadImage(with: url) { result in
//            if case let .success(response) = result {
//                if let type = response.container.type, type.isVideo, let asset = response.container.userInfo[.videoAssetKey] as? AVAsset {
//                    self.asset = asset
//                    Task {
//                        if let videoSize = await getVideoDimensions(asset: asset) {
//                            self.videoSize = videoSize
//                        }
//                    }
//                }
//            }
//        }
//
//        if let task {
//            for await progress in task.progress {
//
//            }
//        }
    }
}

struct VPV: UIViewRepresentable {
    @State var asset:AVAsset
    @State var videoPlayerView:VideoPlayerView
    @Binding var isPlaying:Bool
    
    init(asset: AVAsset, isPlaying:Binding<Bool>) {
        self.videoPlayerView = VideoPlayerView()
        self.asset = asset
        _isPlaying = isPlaying
    }
    
    func makeUIView(context: Context) -> UIView {
        videoPlayerView.asset = asset
        //        videoPlayerView.playerLayer.player?.
        if (isPlaying) {
            videoPlayerView.play()
            videoPlayerView.playerLayer.player?.isMuted = false
        }
        else {
            videoPlayerView.playerLayer.player?.pause()
        }
        return videoPlayerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if (isPlaying) {
            videoPlayerView.play()
            videoPlayerView.playerLayer.player?.isMuted = false
        }
        else {
            videoPlayerView.playerLayer.player?.pause()
            videoPlayerView.playerLayer.player?.isMuted = true
            
        }
    }
}

func getVideoDimensions(asset: AVAsset) async -> CGSize? {
    // Get the video track
    guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
        return nil
    }

    // Get the natural size of the video track
    guard let naturalSize = try? await videoTrack.load(.naturalSize) else { return nil }

    // Get the preferred transform to handle any video orientation
    guard let preferredTransform = try? await videoTrack.load(.preferredTransform) else { return nil }

    // Calculate the corrected video dimensions considering the orientation
    let correctedSize = CGSize(
        width: abs(CGFloat(preferredTransform.a) * naturalSize.width + CGFloat(preferredTransform.c) * naturalSize.height),
        height: abs(CGFloat(preferredTransform.b) * naturalSize.width + CGFloat(preferredTransform.d) * naturalSize.height)
    )

    return correctedSize
}

struct SingleVideoViewer_Previews: PreviewProvider {
    static var previews: some View {
        let content1 = "one image: https://www.volvocars.com/images/v/-/media/applications/pdpspecificationpage/my24/ex90-electric/reveal/hero/desktop/04-headlight-video.mp4 dunno"

        let urlsFromContent = getImgUrlsFromContent(content1)

        SingleVideoViewer(url:urlsFromContent[0],  pubkey: "dunno", videoWidth: UIScreen.main.bounds.width, isFollowing: true)
    }
}
