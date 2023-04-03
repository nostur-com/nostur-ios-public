//
//  ArticleFormatting.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/03/2023.
//

import SwiftUI
import Nuke
import NukeUI
import NukeVideo
import AVFoundation

// Renders embeds (VIEWS), not links (in TEXT)
struct ContentRenderer: View { // VIEW things
    
    let vPost:VPost
    let isDetail:Bool
    @ObservedObject var event:Event
    @State var isPlaying = false
    
    init(vPost: VPost, isDetail:Bool = false) {
        self.isDetail = isDetail
        self.vPost = vPost
        self.event = vPost.event
        ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
    }
    
    var firstQuote:MarkdownElement? {
        vPost.renderedElements.first(where: { element in
            if case .note1 = element {
                return true
            }
            return false
        })
    }
    
    // If not detail we filter some items to keep short for many rows
    var rendered:[MarkdownElement] {
        if isDetail {
            return vPost.renderedElements
        }
        var gotVideo = false
        return vPost.renderedElements
            .filter { element in
                if case .video = element {
                    if (!gotVideo) {
                        gotVideo = true
                        return true
                    }
                    return false
                }
                if case .note1 = element {
                    return element == firstQuote
                }
                else {
                    return true
                }
            }
    }
    
    @State var f:FullScreenItem?
    
    var body: some View {
        VStack(alignment:.leading, spacing:0) {
            ForEach(rendered.indices, id:\.self) { index in
                switch rendered[index] {
                    case .plain(let text):
                        Text(text)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.leading)
                            .accentColor(Color("AccentColor"))
                            .tint(Color("AccentColor"))
                            .lineSpacing(3)
                    case .note1(let noteId):
                        QuoteById(id: hex(noteId))
                            .padding(.vertical, 5)
//                            .frame(maxWidth: .infinity, maxHeight:400, alignment: .leading)
                    case .noteId(let hex):
                        QuoteById(id: hex)
                            .padding(.vertical, 5)
//                            .frame(maxWidth: .infinity, maxHeight:400, alignment: .leading)
                    case .text(let attributedString):
                        Text(attributedString)
                            .textSelection(.enabled)
                            .multilineTextAlignment(TextAlignment.leading)
                            .foregroundColor(.primary)
                            .accentColor(Color("AccentColor"))
                            .tint(Color("AccentColor"))
                            .lineSpacing(3)
//                            .padding(0)
//                            .frame(maxWidth: .infinity)
//                            .padding(.vertical, 5)
//                                                    .frame(maxWidth: .infinity, alignment: .leading)
                    case .lnbc(let text):
                        LightningInvoice(invoice: text)
                    case .video(let url):
                        LazyVStack {
                            LazyImage(url: url) { state in
                                if let container = state.imageContainer {
                                    if let type = container.type, type.isVideo, let asset = container.userInfo[.videoAssetKey] as? AVAsset {
                                        VPV(asset: asset, isPlaying: $isPlaying)
                                            .onTapGesture {
                                                isPlaying.toggle()
                                            }
                                            .frame(height: 250)
                                            .background(Color("LightGray"))
                                            .onAppear {
                                                configureAudioSession()
                                            }
                                            .onDisappear {
                                                isPlaying = false
                                            }
                                            .background(Color.black)
                                            .overlay(
                                                    Button(action: {
                                                        if isPlaying {
                                                            isPlaying = false
                                                        } else {
                                                            isPlaying = true
                                                        }
                                                    }) {
                                                        Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                                                            .resizable()
                                                            .scaledToFit()
                                                            .padding(80)
                                                    }.opacity(isPlaying ? 0 : 1)
                                            )
                                    }
                                }
                                
                            }
                            .pipeline(ImageProcessing.shared.video)
                            .frame(height: 250)
                            .background(Color("LightGray"))
                        }
                    case .image(let url):
                        SingleMediaViewer(url: url)
                            .frame(height: 250)
                            .padding(5)
                    default:
                        EmptyView()
                }
            }
        }
//        .frame(maxWidth: .infinity, maxHeight:450, alignment: .leading)
    }
    
    func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }
    }
}

struct RowContentRenderer_Previews: PreviewProvider {
    
    static var previews: some View {
        
        ScrollView {
            if let vPost = PreviewFetcher.fetchVPost("9b34fd9a53398fb51493d68ecfd0d64ff922d0cdf5ffd8f0ffab46c9a3cf54e3") {
                ContentRenderer(vPost: vPost)
            }
            if let vPost = PreviewFetcher.fetchVPost("102177a51af895883e9256b70b2caff6b9ef90230359ee20f6dc7851ec9e5d5a") {
                ContentRenderer(vPost: vPost)
            }
            Spacer()
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

//    func play() {
//        player.play()
//    }
//
//    func pause() {
//        player.pause()
//    }
}


//struct VPV: UIViewControllerRepresentable {
//    let asset: AVAsset
//    @Binding var isPlaying:Bool
//
//    init(asset: AVAsset, isPlaying:Binding<Bool>) {
//        self.asset = asset
//        _isPlaying = isPlaying
//    }
//
//    func makeUIViewController(context: Context) -> AVPlayerViewController {
//        let playerViewController = AVPlayerViewController()
//        playerViewController.player = self.player
//        playerViewController.showsPlaybackControls = true
//        playerViewController.allowsPictureInPicturePlayback = true
//        playerViewController.delegate = context.coordinator
//        playerViewController.player?.play()
//
//        return playerViewController
//    }
//
//    func makeCoordinator() -> Coordinator {
//        Coordinator(self)
//    }
//
//    //    func makeUIView(context: Context) -> UIView {
//    //        let playerView = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
//    //        let player = AVPlayer(url: videoURL)
//    //        let playerLayer = AVPlayerLayer(player: player)
//    //        playerLayer.videoGravity = .resizeAspectFill
//    //        playerLayer.frame = playerView.bounds
//    //        playerView.layer.addSublayer(playerLayer)
//    //
//    //        player.play()
//    //
//    //        return playerView
//    //    }
//
//    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
//        if (isPlaying) {
//            self.player.play()
//        }
//        else {
//            self.player.play()
//        }
//    }
//
//    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
//        var parent: AVP
//
//        init(_ parent: AVP) {
//            self.parent = parent
//        }
//    }
//
//    //    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
//    //        var parent: AVP
//    //
//    //        init(_ parent: AVP) {
//    //            self.parent = parent
//    //        }
//    //    }
//}


enum MarkdownElement: Hashable {
    case plain(String)
    case text(AttributedString)
    case note1(String)
    case noteId(String)
    case lnbc(String)
    case link(String, URL)
    case image(URL)
    case video(URL)
}


struct QuoteById: View {

    let id:String
    //    @ObservedObject var vm:EventVM // no vm want fr is not updating after receiving from websocket

    @FetchRequest
    var events:FetchedResults<Event>
    //
    init(id:String) {
        self.id = id
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "id == %@", id)
        fr.fetchLimit = 1
        _events = FetchRequest(fetchRequest: fr)
    }

    var body: some View {
        if let event = events.first {
            QuotedNoteFragmentView(vPost: event.toVPost()!)
        }
        else {
            ProgressView()
                .hCentered()
                .onAppear {
                    print("🟢 Fetching for QuotedNoteFragmentView \(id)")
                    SocketPool.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEventAndReferences(id: id)))
                }
        }
    }
}

struct Kind1ById: View {

    let id:String
    let hideFooter:Bool
    //    @ObservedObject var vm:EventVM // no vm want fr is not updating after receiving from websocket

    @FetchRequest
    var events:FetchedResults<Event>
    //
    init(id:String, hideFooter:Bool = true) {
        self.id = id
        self.hideFooter = hideFooter
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "id == %@", id)
        fr.fetchLimit = 1
        _events = FetchRequest(fetchRequest: fr)
    }

    var body: some View {
        if let event = events.first {
            NoteRow.Kind1(vPost: event.toVPost()!, hideFooter:hideFooter)
        }
        else {
            ProgressView()
                .hCentered()
                .onAppear {
                    print("🟢 Fetching for Kind1ById \(id)")
                    SocketPool.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: id)))
//                    SocketPool.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEventAndReferences(id: id)))
                }
        }
    }
}
