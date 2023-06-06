import SwiftUI
import NukeUI
import Nuke
import NukeVideo
import AVFoundation

@MainActor
struct SingleVideoViewer: View {
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
    @State var loadNonHttpsAnyway = false

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
                if let asset, let videoSize {
                    
                    let scaledDimensions = getScaledVideoDimensions(videoSize: videoSize, availableWidth: videoWidth, maxHeight: 600)
                    
                    UIVideoViewer(asset: asset, isPlaying: $isPlaying)
                        .highPriorityGesture(
                            TapGesture().onEnded { _ in
                                isPlaying.toggle()
                            }
                        )
                        .frame(width: scaledDimensions.width, height: scaledDimensions.height)
                        .background(Color.black)
                        .onDisappear {
                            if isPlaying {
                                isPlaying = false
                            }
                        }
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

enum VideoLoadingState {
    case initial
    case loading
    case ready
    case error
    case cancelled
}

struct SingleVideoViewer_Previews: PreviewProvider {
    static var previews: some View {
        
    // Use ImageDecoderRegistory to add the decoder to the
    let _ = ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
        
//        let content1 = "one image: https://www.volvocars.com/images/v/-/media/applications/pdpspecificationpage/my24/ex90-electric/reveal/hero/desktop/04-headlight-video.mp4 dunno"

        let content1 = "one image: https://nostur.com/test1.mp4 dunno"

        let urlsFromContent = getImgUrlsFromContent(content1)

        SingleVideoViewer(url:urlsFromContent[0],  pubkey: "dunno", videoWidth: UIScreen.main.bounds.width, isFollowing: true)
            .previewDevice(PreviewDevice(rawValue: "iPhone 14"))
    }
}

