//
//  ImageViewer.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/03/2023.
//

import SwiftUI
import Nuke
import NukeUI
//import AnimatedImage
//import AVKit
import AVKit
import AVFoundation


//extension Data {
//    func getAVAsset() -> AVAsset {
//        let directory = NSTemporaryDirectory()
//        let fileName = "\(NSUUID().uuidString).mov"
//        let fullURL = NSURL.fileURL(withPathComponents: [directory, fileName])
//        try! self.write(to: fullURL!)
//        let asset = AVAsset(url: fullURL!)
//        return asset
//    }
//}

struct FullScreenItem : Identifiable {
    var url:URL
    var id:String { url.absoluteString }
}

// For use in NoteRow, not PostDetail
struct MediaViewer: View {
    @EnvironmentObject var ns:NosturState // Only needed for `eventIsRestricted`
    let imgUrls:[URL]
    let pubkey:String
    
    @State var fullScreenItem:FullScreenItem?
    @State var imagesShown = false
    @State var isPlaying = false
    
    init(imgUrls: [URL], pubkey:String) {
        self.imgUrls = imgUrls
        self.pubkey = pubkey
    }
    
    init(content:String, pubkey:String) {
        self.imgUrls = getImgUrlsFromContent(content)
        self.pubkey = pubkey
    }
    
    var body: some View {
        VStack(alignment: .center) {
            if (imgUrls.count > 1) {
                if (imagesShown) {
                    GeometryReader { geometry in
                        let side = geometry.frame(in: .local).size.width / 3
                        
                        ScrollView(.horizontal) {
                            LazyHStack {
                                ForEach(0..<imgUrls.prefix(20).count, id: \.self) { index in
                                    if ([".mp4",".mov"].contains(imgUrls[index].absoluteString.suffix(4))) {
                                        //                                        AVP(videoURL: imgUrls[index])
//                                        AVP(videoURL: imgUrls[index], width: side, height: 200, contentMode: .scaleAspectFit, isPlaying: $isPlaying)
                                        VideoPlayerViewer(videoURL: imgUrls[index], width: side, height: 200)
//                                            .onTapGesture {
//                                                isPlaying.toggle()
//                                            }
                                            .onAppear {
                                                configureAudioSession()
                                            }
                                    }
                                    else if (imgUrls[index].absoluteString.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                                        LazyImage(url: imgUrls[index]) { state in
                                            if let container = state.imageContainer {
                                                if container.type == .gif, let gifData = container.data {
                                                    
                                                    GIFImage(data: gifData)
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fit)
                                                        .frame(height: 200)
                                                        .onTapGesture {
                                                            fullScreenItem = FullScreenItem(url: imgUrls[index])
                                                        }
                                                }
                                                else if let image = state.image {
                                                    image
                                                        .resizable()
                                                        .scaledToFit()
                                                        .frame(width: side, height: 200)
                                                        .onTapGesture {
                                                            fullScreenItem = FullScreenItem(url: imgUrls[index])
                                                        }
                                                }
                                                else {
                                                    CenteredProgressView()
                                                }
                                            }
                                            else {
                                                CenteredProgressView()
                                            }
                                        }
                                        .pipeline(ImageProcessing.shared.content) // NO PROCESSING FOR ANIMATED GIF (BREAKS ANIMATION)
                                        .priority(.low)
                                    }
                                    else {
                                        LazyImage(url: imgUrls[index]) { state in
                                            if let image = state.image {
                                                image
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: side, height: 200)
                                                    .onTapGesture {
                                                        fullScreenItem = FullScreenItem(url: imgUrls[index])
                                                    }
                                            }
                                            else {
                                                CenteredProgressView()
                                            }
                                        }
                                        .pipeline(ImageProcessing.shared.content) // No processing again here, we probably never show the image again
                                        
                                    }
                                }
                            }
                        }
                        .fullScreenCover(item: $fullScreenItem, content: { item in
                            FullImageViewer(fullImageURL:item.url)
                        })
                    }
                    .frame(height: 200)
                    //                    .background(.regularMaterial)
                }
                else {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("Tap to load media")
                            Spacer()
                        }
                        Spacer()
                    }
                    .frame(height: 200)
                    .background(.regularMaterial)
                    .cornerRadius(10)
                    .onTapGesture {
                        imagesShown = true
                    }
                }
            }
            else if (imgUrls.count == 1) {
                if (imagesShown) {
                    GeometryReader { geo in
                        if let imgUrl = imgUrls.first {
                            if ([".mp4",".mov"].contains(imgUrl.absoluteString.suffix(4))) {
                                //                                AVP(videoURL: imgUrl)
//                                AVP(videoURL: imgUrl, width: geo.size.width, height: geo.size.height, contentMode: .scaleAspectFit, isPlaying: $isPlaying)
                                VideoPlayerViewer(videoURL: imgUrl, width: geo.size.width, height: geo.size.height)
//                                    .onTapGesture {
//                                        isPlaying.toggle()
//                                    }
                                    .onAppear {
                                        configureAudioSession()
                                    }
                            }
                            else if (imgUrl.absoluteString.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                                LazyImage(url: imgUrl) { state in
                                    if let container = state.imageContainer {
                                        if container.type == .gif, let gifData = container.data {
                                            GIFImage(data: gifData)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: geo.size.width, height: 200)
                                                .onTapGesture {
                                                    fullScreenItem = FullScreenItem(url: imgUrl)
                                                }
                                        }
                                        else if let image = state.image {
                                            image
                                                .resizable()
                                                .scaledToFit()
                                                .onTapGesture {
                                                    fullScreenItem = FullScreenItem(url: imgUrl)
                                                }
                                        }
                                        else {
                                            CenteredProgressView()
                                        }
                                    }
                                    else {
                                        CenteredProgressView()
                                    }
                                }
                                .pipeline(ImageProcessing.shared.content) // NO PROCESSING FOR ANIMATED GIF (BREAKS ANIMATION)
                                .priority(.low)
                            }
                            else {
                                LazyImage(url: imgUrl) { state in
                                    if let image = state.image {
                                        image
                                            .resizable()
                                            .scaledToFit()
                                            .onTapGesture {
                                                fullScreenItem = FullScreenItem(url: imgUrl)
                                            }
                                    }
                                    else {
                                        CenteredProgressView()
                                    }
                                }
                                .pipeline(ImageProcessing.shared.content) // No processing again here, we probably never show the image again
                            }
                        }
                    }
                    .frame(height: 200)
                    .fullScreenCover(item: $fullScreenItem, content: { item in
                        FullImageViewer(fullImageURL:item.url)
                    })
                }
                else {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("Tap to load media")
                            Spacer()
                        }
                        Spacer()
                    }
                    .frame(height: 200)
                    .background(.regularMaterial)
                    .cornerRadius(10)
                    .onTapGesture {
                        imagesShown = true
                    }
                }
            }
            else {
                EmptyView()
            }
        }
        .onAppear {
            imagesShown = !SettingsStore.shared.restrictAutoDownload || ns.isFollowing(pubkey)
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

struct FullImageViewer: View {
    
    @Environment(\.dismiss) var dismiss
    //    @Binding var fullImageIsShown:Bool
    var fullImageURL:URL
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var position: CGSize = .zero
    @State private var newPosition: CGSize = .zero
    @State var isPlaying = true
    @State private var gestureStartTime: Date?

    
    var body: some View {
        
        let magnifyAndDragGesture = MagnificationGesture()
            .onChanged { value in
                let delta = value / self.lastScale
                self.lastScale = value
                self.scale *= delta
            }
            .onEnded { value in
                self.lastScale = 1.0
            }
            .simultaneously(with: DragGesture()
                .onChanged { value in
                    self.position.width = self.newPosition.width + value.translation.width
                    self.position.height = self.newPosition.height + value.translation.height
                }
                .onEnded { value in
                    self.newPosition = self.position
                }
            )
            .simultaneously(with: DragGesture(minimumDistance: 3.0, coordinateSpace: .local)
                .onChanged { value in
                    if gestureStartTime == nil {
                        gestureStartTime = Date()
                    }
                }
                .onEnded { value in
                    print(value.translation)
                    guard let startTime = gestureStartTime else { return }
                                         let duration = Date().timeIntervalSince(startTime)
                                         let quickSwipeThreshold: TimeInterval = 0.25 // Adjust this value as needed
                    print(duration)
                    switch(value.translation.width, value.translation.height) {
                            //                    case (...0, -30...30):  print("left swipe")
                            //                    case (0..., -30...30):  print("right swipe")
                            //                    case (-100...100, ...0):  print("up swipe")
                        case (-100...100, 0...):
                            if duration < quickSwipeThreshold {
                                dismiss()
                            }
                            else {
                                gestureStartTime = nil
                            }
                        default:
                            print("no clue")
                            gestureStartTime = nil
                    }
                }
            )
        
        GeometryReader { geo in
            ZStack {
                VStack {
                    if ([".mp4",".mov"].contains(fullImageURL.absoluteString.suffix(4))) {
                        //                        AVP(videoURL: fullImageURL)
//                        AVP(videoURL: fullImageURL, width: geo.size.width, height: geo.size.height, contentMode: .scaleAspectFit, isPlaying: $isPlaying)
//                            .onTapGesture {
//                                isPlaying.toggle()
//                            }
                        VideoPlayerViewer(videoURL: fullImageURL, width: geo.size.width, height: geo.size.height)
                    }
                    else {
                        LazyImage(request: ImageRequest(url: fullImageURL)) { state in
                            if state.error != nil {
                                Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
                                    .centered()
                                    .background(Color("LightGray").opacity(0.2))
                                    .onAppear {
                                        print("Failed to load image: \(state.error?.localizedDescription ?? "")")
                                    }
                            }
                            else if let container = state.imageContainer, container.type ==  .gif, let data = container.data {
                                GIFImage(data: data)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .scaleEffect(scale)
                                    .offset(position)
                                    .gesture(magnifyAndDragGesture)
                                    .onTapGesture {
                                        withAnimation {
                                            scale = 1.0
                                        }
                                    }
                            }
                            else if let image = state.image {
                                image
                                    .resizable()
                                    .resizable()
                                    .scaledToFit()
                                    .scaleEffect(scale)
                                    .offset(position)
                                    .gesture(magnifyAndDragGesture)
                                    .onTapGesture {
                                        withAnimation {
                                            scale = 1.0
                                        }
                                    }
                            }
                            else if state.isLoading { // does this conflict with showing preview images??
                                HStack(spacing: 5) {
                                    ProgressView()
                                    ImageProgressView(progress: state.progress)
                                    Image(systemName: "multiply.circle.fill")
                                        .padding(10)
                                }
                                .centered()
                                .background(Color("LightGray"))
                            }
                            else {
                                Color("LightGray").opacity(0.2)
                            }
                        }
                        .pipeline(ImageProcessing.shared.content)
                        .priority(.high)
                    }
                }
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .padding(30)
                            .onTapGesture {
                                dismiss()
                            }
                            .zIndex(10)
                    }
                    Spacer()
                }
                .onTapGesture {
                    dismiss()
                    //                fullImageIsShown = false
                }
            }
        }
    }
}

func getImgUrlsFromContent(_ content:String) -> [URL] {
    var urls:[URL] =  []
    let regex = try! NSRegularExpression(pattern: "(?i)https?:\\/\\/\\S+?\\.(?:mp4|mov|png|jpe?g|gif|webp|bmp)(\\?\\S+){0,1}\\b")
    let range = NSRange(content.startIndex..<content.endIndex, in: content)
    let matches = regex.matches(in: content, range: range)
    for match in matches {
        let url = (content as NSString).substring(with: match.range)
        if let urlURL = URL(string: url) {
            urls.append(urlURL)
        }
    }
    return urls
}

struct ImageViewer_Previews: PreviewProvider {
    static var previews: some View {
        
//        let content4 = ###"some images: https://nostur.com/screenshots/badges.png https://nostur.com/screenshots/multi-account.jpg https://nostur.com/screenshots/tagging.gif\nhttps://nostur.com/screenshots/zaps-revamped.png https://nostur.com/screenshots/detail-pane-ipad.jpg"###
//        
        
        let content1 = "one image: https://nostur.com/screenshots/badges.png dunno"
        
        let urlsFromContent = getImgUrlsFromContent(content1)
        
        List {
            //            LazyImage(url: URL(string: "https://nostur.com/screenshots/badges.png")!)
            //                .frame(height: 200)
            //                .padding(20)
            //                .listRowInsets(EdgeInsets())
            //
            //            ImageViewer(content: content1)
            MediaViewer(imgUrls: urlsFromContent, pubkey: "")
                .listRowInsets(EdgeInsets())
        }
        .listStyle(.inset)
        .withPreviewEnvironment()
    }
}
