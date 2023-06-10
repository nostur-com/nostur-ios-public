//
//  UIV.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/06/2023.
//

import SwiftUI

import SwiftUI
import NukeUI
import Nuke
import NukeVideo
import AVFoundation

// TODO: Fix full screen VideoPlayerView in FullImageViewer is not used anymore??

@MainActor
struct XSingleVideoViewer: View {
    let url:URL
    let pubkey:String
    var height:CGFloat?
    let videoWidth:CGFloat
    let isFollowing:Bool
    var fullWidth:Bool = false
    @State var videoState:XVideoLoadingState = .initial
    @State var videoShown = true
    @State var isPlaying = false
    @State var isMuted = false
    @State var asset:AVAsset? = nil
    @State var scaledDimensions:CGSize? = nil
    @State var videoLength:String? = nil
    @State var task:AsyncImageTask? = nil
    @State var percent = 0
    @State var autoplay = false
    @State var loadNonHttpsAnyway = false
    @State var didTap = false
    
    var body: some View {
        VStack {
            if url.absoluteString.prefix(7) == "http://" && !loadNonHttpsAnyway {
                VStack {
                    Text("non-https media blocked", comment: "Displayed when an image in a post is blocked")
                    Button(String(localized: "Show anyway", comment: "Button to show the blocked content anyway")) {
                        loadNonHttpsAnyway = true
                        videoShown = true
                        autoplay = true
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
                if let asset, let scaledDimensions {
                    UIV(asset: asset, isPlaying: $isPlaying, isMuted: $isMuted)
                        .frame(width: scaledDimensions.width, height: scaledDimensions.height)
                        .background(Color.black)
                        .onDisappear {
                            if isPlaying {
                                isPlaying = false
                            }
                        }
                        .overlay(alignment:.bottomLeading) {
                            if !didTap, let videoLength {
                                Text(videoLength)
                                    .foregroundColor(.white)
                                    .fontWeight(.bold)
                                    .padding(3)
                                    .background(.black)
                                    .padding(5)
                            }
                        }
                        .overlay(
                            Button(action: {
                                didTap = true
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
                            }.opacity(didTap ? 0 : 1)
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

func getVideoLength(asset:AVAsset) async -> String? {
    guard let duration = try? await asset.load(.duration) else {
        L.og.debug("getVideoLength: Unable to load udration")
        return nil
    }
    
    let seconds = CMTimeGetSeconds(duration)
    let secondsText = String(format: "%02d", Int(seconds) % 60)
    let minutesText = String(format: "%02d", Int(seconds) / 60)
    return "\(minutesText):\(secondsText)"
}

enum XVideoLoadingState {
    case initial
    case loading
    case ready
    case error
    case cancelled
}

struct XSingleVideoViewer_Previews: PreviewProvider {
    static var previews: some View {
        
        // Use ImageDecoderRegistory to add the decoder to the
        let _ = ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
        
        let content1 = "one image: https://nostur.com/test1.mp4 dunno"
        
        let urlsFromContent = getImgUrlsFromContent(content1)
        
        XSingleVideoViewer(url:urlsFromContent[0],  pubkey: "dunno", videoWidth: UIScreen.main.bounds.width, isFollowing: true)
            .previewDevice(PreviewDevice(rawValue: "iPhone 14"))
    }
}



import SwiftUI
import UIKit
import AVFoundation
import AVKit
import NukeVideo

struct UIV: UIViewControllerRepresentable {
    
    @State var asset:AVAsset
//    @State var videoPlayerView:NosturVideoPlayerView
    @Binding var isPlaying:Bool
    @Binding var isMuted:Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let avpc = AVPlayerViewController()

        let playerItem = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer(playerItem: playerItem)
        player.isMuted = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .pause
        
        
        avpc.player = player
        avpc.exitsFullScreenWhenPlaybackEnds = false
        avpc.videoGravity = .resizeAspectFill
        avpc.allowsPictureInPicturePlayback = true
        avpc.delegate = context.coordinator
        avpc.showsPlaybackControls = true
        avpc.canStartPictureInPictureAutomaticallyFromInline = true

        return avpc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if isPlaying {
            uiViewController.entersFullScreenWhenPlaybackBegins = true
            uiViewController.player?.play()
        }
        else {
            uiViewController.player?.pause()
        }
    }

    typealias UIViewControllerType = AVPlayerViewController
    
    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate, AVPictureInPictureControllerDelegate {
        
    }

    init(asset: AVAsset, isPlaying:Binding<Bool>, isMuted:Binding<Bool>) {
        do { try AVAudioSession.sharedInstance().setActive(true) }
        catch { }
//        self.videoPlayerView = NosturVideoPlayerView()
        self.asset = asset
        _isPlaying = isPlaying
        _isMuted = isMuted
    }

    
}
