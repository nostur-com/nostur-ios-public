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

enum VideoLoadingState {
    case initial
    case loading
    case ready
    case error
    case cancelled
}

@MainActor
struct SingleVideoViewer: View {
    
    @EnvironmentObject var ns:NosturState // Only needed for `imagesShown`
    let url:URL
    let pubkey:String
    var height:CGFloat?
    let videoWidth:CGFloat
    let isFollowing:Bool
    var fullWidth:Bool = false
    @State var videoState:VideoLoadingState = .initial
    @State var videoShown = false
    @State var isPlaying = false
    @State var asset:AVAsset? = nil
    @State var videoSize:CGSize? = nil
    @State var task:AsyncImageTask? = nil
    @State var percent = 0
    @State var autoplay = false

    
    var body: some View {
        VStack {
            if url.absoluteString.prefix(7) == "http://" {
                Text("non-https media blocked")
                   .centered()
                   .frame(height: fullWidth ? 600 : 250)
                   .background(Color("LightGray").opacity(0.2))
            }
            else if videoShown {
                if let asset, let videoSize {
                    
                    let scaledWidth = videoWidth / videoSize.width
                    let scaledHeight = videoSize.height > videoSize.width && videoSize.height > 600 ? 600 : videoSize.height * scaledWidth
                    
                    VPV(asset: asset, isPlaying: $isPlaying)
                        .highPriorityGesture(
                            TapGesture().onEnded { _ in
                                isPlaying.toggle()
                            }
                        )
                        .frame(height: scaledHeight)
                        .background(Color.black)
                        .onDisappear { isPlaying = false }
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
                        .hCentered()
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
                else if videoState == .loading {
                    HStack(spacing: 5) {
                        ProgressView()
                        Text("\(percent)%")
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
                Text("Tap to load video")
                    .centered()
                    .frame(height: fullWidth ? 600 : 250)
                    .background(Color("LightGray").opacity(0.2))
                    .highPriorityGesture(
                        TapGesture()
                            .onEnded { _ in
                                videoShown = true
                                autoplay = true
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
                    if let videoSize = await getVideoDimensions(asset: asset) {
                        self.videoSize = videoSize
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
