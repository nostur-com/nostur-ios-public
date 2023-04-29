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
import Combine

// Renders embeds (VIEWS), not links (in TEXT)
struct ContentRenderer: View { // VIEW things
    let vPost:VPost
    let isDetail:Bool
    let fullWidth:Bool
    let availableWidth:CGFloat
    @ObservedObject var event:Event
    @State var isPlaying = false
    @State var renderedElements:[MarkdownElement]
    @State var subscriptions = Set<AnyCancellable>()
    
    init(vPost: VPost, isDetail:Bool = false, fullWidth:Bool = false, availableWidth:CGFloat) {
        self.isDetail = isDetail
        self.vPost = vPost
        self.event = vPost.event
        self.fullWidth = fullWidth
        self.availableWidth = availableWidth
        _renderedElements = State(initialValue: isDetail ? vPost.renderedElementsDetail : vPost.renderedElements )
    }
    
    @State var f:FullScreenItem?
    @State private var viewSize: CGSize = .zero
    
    var body: some View {
        VStack(alignment:.leading, spacing:0) {
            ForEach(renderedElements.indices, id:\.self) { index in
                switch renderedElements[index] {
                        //                    case .plain(let text):
                        //                        Text(text)
                        //                            .textSelection(.enabled)
                        //                            .multilineTextAlignment(.leading)
                        //                            .accentColor(Color("AccentColor"))
                        //                            .tint(Color("AccentColor"))
                        //                            .lineSpacing(3)
                    case .note1(let noteId):
                        if let noteHex = hex(noteId) {
                            QuoteById(id: noteHex)
                                .padding(.vertical, 5)
                                .padding(.horizontal, fullWidth ? 10 : 0)
                        }
                        else {
                            let _ = print("🔴🔴🔴🔴 Problem converting \(noteId) to hex")
                            EmptyView()
                        }
                        //                            .frame(maxWidth: .infinity, maxHeight:400, alignment: .leading)
                    case .noteHex(let hex):
                        QuoteById(id: hex)
                            .padding(.vertical, 5)
                            .padding(.horizontal, fullWidth ? 10 : 0)
                        //                            .frame(maxWidth: .infinity, maxHeight:400, alignment: .leading)
                    case .text(let attributedString):
                        // BROKEN SHIT
                        //                            Text(string)
                        //                            .fixedSize(horizontal: false, vertical: true)
                        //                            .overlay(MarkdownText(string))
                        Text(attributedString)
                            .textSelection(.enabled)
                            .multilineTextAlignment(TextAlignment.leading)
                            .foregroundColor(.primary)
                            .accentColor(Color("AccentColor"))
                            .tint(Color("AccentColor"))
                            .lineSpacing(3)
                            .padding(.horizontal, fullWidth ? 10 : 0)
                        //                            .padding(0)
                        //                            .frame(maxWidth: .infinity)
                        //                            .padding(.vertical, 5)
                        //                                                    .frame(maxWidth: .infinity, alignment: .leading)
                    case .lnbc(let text):
                        LightningInvoice(invoice: text)
                            .padding(.horizontal, fullWidth ? 10 : 0)
                    case .video(let url):
                        LazyImage(url: url) { state in
                            if let container = state.imageContainer {
                                if let type = container.type, type.isVideo, let asset = container.userInfo[.videoAssetKey] as? AVAsset {
                                    
                                    if let videoSize = getVideoDimensions(asset: asset) {
                                        let scaledWidth = availableWidth / videoSize.width
                                        let scaledHeight = videoSize.height * scaledWidth
                                        
                                        VPV(asset: asset, isPlaying: $isPlaying)
                                            .onTapGesture {
                                                isPlaying.toggle()
                                            }
                                            .frame(height: scaledHeight)
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
                                    }
                                    else {
                                        Label("Failed to load video", systemImage: "exclamationmark.triangle.fill")
                                            .centered()
                                    }
                                }
                                else if state.isLoading {
                                    ProgressView()
                                        .centered()
                                }
                            }
                            else if state.isLoading {
                                ProgressView()
                                    .centered()
                            }
                            else {
                                Label("Failed to load video", systemImage: "exclamationmark.triangle.fill")
                                    .centered()
                            }
                        }
                        .pipeline(ImageProcessing.shared.video)
                        .frame(minHeight: 250)
                        .background(Color("LightGray"))
                    case .image(let url):
                        SingleMediaViewer(url: url, pubkey: vPost.event.pubkey, imageWidth: availableWidth, isFollowing: vPost.following, fullWidth: fullWidth)
                            .padding(.vertical, 5)
                    case .linkPreview(let url):
                        // TODO: do no link preview if restrictAutoDownload...
                        LinkPreviewView(url: url)
                            .padding(.horizontal, fullWidth ? 10 : 0)
                            .padding(.vertical, 5)
                    case .postPreviewImage(let uiImage):
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 600)
                            .padding(.top, 10)
                    default:
                        EmptyView()
                }
            }
        }
        //        .frame(maxWidth: .infinity, maxHeight:450, alignment: .leading)
        .onAppear {
            guard !vPost.event.isPreview else { return }
            event.objectWillChange
                .sink {
                    
                    let followingKeys = NosturState.shared.followingPublicKeys
                    EventsProvider.shared.container.performBackgroundTask { context in
                        let transformer = VPostTransformer(context, followingKeys: followingKeys) // Tranform in bg
                     
                        guard let privateEvent = context.object(with: event.objectID) as? Event else { return }
                        var renderedElements = transformer.renderElements(privateEvent).0
                        
                        let firstQuote = renderedElements.first(where: { element in
                            if case .note1 = element {
                                return true
                            }
                            return false
                        })
                        
                        var renderedForRow:[MarkdownElement] {
                            var gotVideo = false
                            return renderedElements
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
                                                
                        DispatchQueue.main.async {
                            self.renderedElements = isDetail ? renderedElements : renderedForRow
                        }
                    }
    
                }
                .store(in: &subscriptions)
        }
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
            VStack {
                if let vPost = PreviewFetcher.fetchVPost("9b34fd9a53398fb51493d68ecfd0d64ff922d0cdf5ffd8f0ffab46c9a3cf54e3") {
                    ContentRenderer(vPost: vPost, availableWidth: UIScreen.main.bounds.width)
                }
                if let vPost = PreviewFetcher.fetchVPost("102177a51af895883e9256b70b2caff6b9ef90230359ee20f6dc7851ec9e5d5a") {
                    ContentRenderer(vPost: vPost, availableWidth: UIScreen.main.bounds.width)
                }
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

struct QuoteById: View {
    
    let id:String
    //    @ObservedObject var vm:EventVM // no vm want fr is not updating after receiving from websocket
    
    @FetchRequest
    var events:FetchedResults<Event>
    
    @State var vPost:VPost?
    
    init(id:String) {
        self.id = id
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "id == %@", id)
        fr.fetchLimit = 1
        _events = FetchRequest(fetchRequest: fr)
    }
    
    var body: some View {
        if let event = events.first {
            if let vPost = vPost {
                QuotedNoteFragmentView(vPost: vPost)
            }
            else {
                Color.clear
                    .frame(height: 150)
                    .task {
                        let followingKeys = NosturState.shared.followingPublicKeys
                        EventsProvider.shared.container.performBackgroundTask { context in
                            let transformer = VPostTransformer(context, followingKeys: followingKeys) // Tranform in bg
                            if let vPost = transformer.toVPost(event, forceBg: true) {
                                DispatchQueue.main.async {
                                    self.vPost = vPost
                                }
                            }
                        }
                    }
            }
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
    let fullWidth:Bool
    //    @ObservedObject var vm:EventVM // no vm want fr is not updating after receiving from websocket
    
    @FetchRequest
    var events:FetchedResults<Event>
    //
    init(id:String, hideFooter:Bool = true, fullWidth:Bool = false) {
        self.id = id
        self.hideFooter = hideFooter
        self.fullWidth = fullWidth
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "id == %@", id)
        fr.fetchLimit = 1
        _events = FetchRequest(fetchRequest: fr)
    }
    
    var body: some View {
        if let vPost = events.first?.toVPost() {
            let _ = print("☠️☠️☠️☠️ toVPost() Kind1ById")
            if fullWidth {
                NoteRow.Kind1(vPost: vPost, hideFooter:hideFooter)
            }
            else {
                NoteRow.Kind1Default(vPost: vPost, hideFooter:hideFooter)
            }
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

func getVideoDimensions(asset: AVAsset) -> CGSize? {
    // Get the video track
    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
        return nil
    }

    // Get the natural size of the video track
    let naturalSize = videoTrack.naturalSize

    // Get the preferred transform to handle any video orientation
    let preferredTransform = videoTrack.preferredTransform

    // Calculate the corrected video dimensions considering the orientation
    let correctedSize = CGSize(
        width: abs(CGFloat(preferredTransform.a) * naturalSize.width + CGFloat(preferredTransform.c) * naturalSize.height),
        height: abs(CGFloat(preferredTransform.b) * naturalSize.width + CGFloat(preferredTransform.d) * naturalSize.height)
    )

    return correctedSize
}

