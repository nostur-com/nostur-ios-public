//
//  FullImageViewer.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/06/2023.
//

import SwiftUI
import Nuke
import NukeUI

struct FullImageViewer: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dim: DIMENSIONS
    @Environment(\.dismiss) private var dismiss
    
    public var fullImageURL: URL
    public var galleryItem: GalleryItem? = nil
    @Binding public var mediaPostPreview: Bool
    @Binding public var sharableImage: UIImage?
    @Binding public var sharableGif: Data?
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var position: CGSize = .zero
    @State private var newPosition: CGSize = .zero
    @State private var isPlaying = true
    @State private var gestureStartTime: Date?
    @State private var post:NRPost? = nil
    @State private var showMiniProfile = false
    @State private var miniProfileAnimateIn = true
    
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
                    guard self.scale != 1.0 || self.position != .zero else { return }
                    self.position.width = self.newPosition.width + value.translation.width
                    self.position.height = self.newPosition.height + value.translation.height
                }
                .onEnded { value in
                    guard self.scale != 1.0 || self.position != .zero else { return }
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
                    L.og.debug("FullimageViewer: \(value.translation.debugDescription)")
                    guard let startTime = gestureStartTime else { return }
                                         let duration = Date().timeIntervalSince(startTime)
                                         let quickSwipeThreshold: TimeInterval = 0.25 // Adjust this value as needed
                    L.og.debug("FullimageViewer: \(duration)")
                    switch(value.translation.width, value.translation.height) {
                            //                    case (...0, -30...30):  print("left swipe")
                            //                    case (0..., -30...30):  print("right swipe")
                            //                    case (-100...100, ...0):  print("up swipe")
                        case (-100...100, 30...):
                            if duration < quickSwipeThreshold {
                                dismiss()
                            }
                            else {
                                gestureStartTime = nil
                            }
                        default:
                        L.og.debug("no clue")
                            gestureStartTime = nil
                    }
                }
            )
            .simultaneously(with: TapGesture(count: 2).onEnded({ _ in
                withAnimation {
                    self.scale = 1.0
                    self.position = .zero
                }
            }))
        
        GeometryReader { geo in
            ZStack {
                themes.theme.listBackground
                LazyImage(request: ImageRequest(url: fullImageURL, options: SettingsStore.shared.lowDataMode ? [.returnCacheDataDontLoad] : [])) { state in
                                if state.error != nil {
                                    if SettingsStore.shared.lowDataMode {
                                        Text(fullImageURL.absoluteString)
                                            .foregroundColor(themes.theme.accent)
                                            .truncationMode(.middle)
                                            .onTapGesture {
                                                openURL(fullImageURL)
                                            }
                                            .onAppear {
                                                sharableGif = nil
                                                sharableImage = nil
                                            }
                                    }
                                    else {
                                        Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
                                            .centered()
                                            .background(themes.theme.lineColor.opacity(0.2))
                                            .onAppear {
                                                L.og.debug("Failed to load image: \(fullImageURL) - \(state.error?.localizedDescription ?? "")")
                                                sharableGif = nil
                                                sharableImage = nil
                                            }
                                    }
                                }
                                else if let container = state.imageContainer, container.type ==  .gif, let data = container.data {
                                    GIFImage(data: data, isPlaying: .constant(true))
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: geo.size.width, height: geo.size.height)
                                        .contentShape(Rectangle())
                                        .scaleEffect(scale)
                                        .offset(position)
                                        .simultaneousGesture(magnifyAndDragGesture)
                                        .onTapGesture {
                                            withAnimation {
                                                mediaPostPreview.toggle()
                                                scale = 1.0
                                            }
                                        }
                                        .onAppear {
                                            sharableGif = data
                                            sharableImage = nil
                                        }
                                }
                                else if let image = state.image {
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .scaleEffect(scale)
                                        .offset(position)
                                        .simultaneousGesture(magnifyAndDragGesture)
                                        .onTapGesture {
                                            withAnimation {
                                                mediaPostPreview.toggle()
                                                scale = 1.0
                                            }
                                        }
                                        .onAppear {
                                            if let image = state.imageContainer?.image {
                                                sharableImage = image
                                                sharableGif = nil
                                            }
                                            else {
                                                sharableGif = nil
                                                sharableImage = nil
                                            }
                                        }
                                }
                                else if state.isLoading { // does this conflict with showing preview images??
                                    HStack(spacing: 5) {
                                        ImageProgressView(state: state)
                                            .frame(width: 48)
                                        Image(systemName: "multiply.circle.fill")
                                            .padding(10)
                                    }
                                    .background(themes.theme.background)
                                    .onAppear {
                                        sharableGif = nil
                                        sharableImage = nil
                                    }
                                }
                                else {
                                    themes.theme.background
                                        .onAppear {
                                            sharableGif = nil
                                            sharableImage = nil
                                        }
                                }
                            }
                            .pipeline(ImageProcessing.shared.content)
                            .priority(.high)
            }
        }
        .onAppear {
            bg().perform {
                guard let galleryItem = galleryItem, let event = galleryItem.event else { return }
                let nrPost = NRPost(event: event)
                DispatchQueue.main.async {
                    self.post = nrPost
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if let post = post, mediaPostPreview && !showMiniProfile {
                MediaPostPreview(post, showMiniProfile: $showMiniProfile)
                    .padding(10)
                    .background(.ultraThinMaterial)
            }
        }
        .overlay(alignment: .topLeading) {
            if let nrPost = post, showMiniProfile {
                ZStack(alignment:.topLeading) {
                    Rectangle()
                        .fill(.thinMaterial)
                        .opacity(0.8)
                        .zIndex(50)
                        .onTapGesture {
                            showMiniProfile = false
                        }
                        .onAppear {
                            miniProfileAnimateIn = true
                        }
                    ProfileOverlayCardContainer(pubkey: nrPost.pubkey, contact: nrPost.contact, zapEtag: nrPost.id)
                        .scaleEffect(miniProfileAnimateIn ? 1.0 : 0.25, anchor: .leading)
                        .opacity(miniProfileAnimateIn ? 1.0 : 0.15)
                        .animation(.easeInOut(duration: 0.15), value: miniProfileAnimateIn)
                        .zIndex(50)
                        .padding(.top, 30)
                        .frame(width: dim.listWidth)
                }
                .onDisappear {
                    miniProfileAnimateIn = false
                }
            }
        }
    }
}

struct MediaPostPreview: View {
    @EnvironmentObject private var themes:Themes
    private let nrPost: NRPost
    @ObservedObject private var pfpAttributes: PFPAttributes
    @Binding private var showMiniProfile: Bool
    @Environment(\.dismiss) var dismiss
    
    init(_ nrPost: NRPost, showMiniProfile: Binding<Bool>) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        _showMiniProfile = showMiniProfile
    }
    
    var body: some View {
        HStack(alignment: .center) {
            ZappablePFP(pubkey: nrPost.pubkey, pfpAttributes: pfpAttributes, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id)
                .frame(width: DIMENSIONS.POST_ROW_PFP_DIAMETER, height: DIMENSIONS.POST_ROW_PFP_DIAMETER)
//                .transaction { t in t.animation = nil }
                .onTapGesture {
                    withAnimation {
                        showMiniProfile = true
                    }
                }
            
            VStack(alignment: .leading) {
                
                Text(pfpAttributes.anyName)
                    .foregroundColor(.primary)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .layoutPriority(2)
                    .onTapGesture {
                        if let nrContact = nrPost.contact {
                            navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName))
                        }
                        else {
                            navigateTo(ContactPath(key: nrPost.pubkey))
                        }
                    }
                    .onAppear {
                        guard nrPost.contact == nil else { return }
                        bg().perform {
                            EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "FullImageViewer.001")
                            QueuedFetcher.shared.enqueue(pTag: nrPost.pubkey)
                        }
                    }
                    .onDisappear {
                        QueuedFetcher.shared.dequeue(pTag: nrPost.pubkey)
                    }                
                
                if let nrContact = pfpAttributes.contact, nrContact.nip05verified, let nip05 = nrContact.nip05 {
                    NostrAddress(nip05: nip05, shortened: nrContact.anyName.lowercased() == nrContact.nip05nameOnly.lowercased())
                            .layoutPriority(3)
                }
                
                
                Text("Posted on \(nrPost.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .onTapGesture {
                        dismiss()
                        navigateTo(nrPost)
                    }
            }
            
            Image(systemName: "chevron.right")
                .padding(10)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                    navigateTo(nrPost)
                }
        }
        .font(.custom("Charter", size: 18))
        .padding(.vertical, 10)
        .lineLimit(1)
        .foregroundColor(Color.secondary)
    }
}

struct FullScreenItem : Identifiable {
    var url:URL
    var id:String { url.absoluteString }
    var galleryItem:GalleryItem?
}

struct FullScreenItem17 : Identifiable {
    var id: Int { index }
    
    var items: [GalleryItem]
    var index: Int
}

struct ShareMediaButton: View {
    
    var sharableImage:UIImage
    @State private var showShareSheet = false

    
    var body: some View {
        Button { showShareSheet = true } label: { Image(systemName: "square.and.arrow.up") }
            .sheet(isPresented: $showShareSheet) {
                let item = NSItemProvider(item: sharableImage.pngData()! as NSData, typeIdentifier: "public.png")
                ActivityView(activityItems: [item])
            }
    }
}

struct ShareGifButton: View {
    
    var sharableGif:Data
    @State private var showShareSheet = false

    
    var body: some View {
        Button { showShareSheet = true } label: { Image(systemName: "square.and.arrow.up") }
            .sheet(isPresented: $showShareSheet) {
                let item = NSItemProvider(item: sharableGif as NSData, typeIdentifier: "com.compuserve.gif")
                ActivityView(activityItems: [item])
            }
                        
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

func getImgUrlsFromContent(_ content:String) -> [URL] {
    var urls:[URL] =  []
    let range = NSRange(content.startIndex..<content.endIndex, in: content)
    let matches = imageRegex.matches(in: content, range: range)
    for match in matches {
        let url = (content as NSString).substring(with: match.range)
        if let urlURL = URL(string: url) {
            urls.append(urlURL)
        }
    }
    return urls
}

let imageRegex = try! NSRegularExpression(pattern: "(?i)https?:\\/\\/\\S+?\\.(?:png|jpe?g|gif|webp|bmp|avif)(\\?\\S+){0,1}\\b")

let mediaRegex = try! NSRegularExpression(pattern: "(?i)https?:\\/\\/\\S+?\\.(?:mp4|mov|m4a|m3u8|mp3|png|jpe?g|gif|webp|bmp|avif)(\\?\\S+){0,1}\\b")

@available(iOS 18.0, *)
#Preview {
    @Previewable @State var mediaPostPreview = true
    @Previewable @State var sharableImage: UIImage? = nil
    @Previewable @State var sharableGif: Data? = nil

    PreviewContainer({ pe in
        pe.parseMessages([###"["EVENT","45460918-9bec-47a2-9d58-a5afdc339ad6",{"content":"{\"banner\":\"https://media3.giphy.com/media/X8MAQUfW29L1GUQSAG/giphy.gif?cid=5e2148863ad49cbaa45cff0fd739f428ee080952fed3dcba&rid=giphy.gif&ct=g\",\"lud06\":\"LNURL1DP68GURN8GHJ7AMPD3KX2AR0VEEKZAR0WD5XJTNRDAKJ7TNHV4KXCTTTDEHHWM30D3H82UNVWQHK6ETPW3UKV6TWV5CNX3ZPU6Y\",\"website\":\"endthefud.org\",\"reactions\":false,\"nip05\":\"lau@nostr.report\",\"picture\":\"https://nostr.build/i/p/6752p.jpeg\",\"display_name\":\"Lau\",\"about\":\"NostReport⚡️#Rita's daddy Noderunner #bitcoin Egodead Psychonaut\",\"name\":\"Lau\"}","created_at":1688661897,"id":"9f21a3230733128c62bc6aafbc31cffa8bf2b0db15de14f8522dfe0fa4d247bb","kind":0,"pubkey":"5a9c48c8f4782351135dd89c5d8930feb59cb70652ffd37d9167bf922f2d1069","sig":"badb9d852daeb1478081bdb475fca95add12825a6f6289f57bcfb0abdb09f28e9f1b1fe5343ad259aa32d56015eeef9ce1e456dc0c2cdbbc84e074d2bbcec2b4","tags":[]}]"###])
        pe.loadMedia()
    }) {
        if let p = PreviewFetcher.fetchEvent("bf0ca9422b83a35fd3384d4149314bfff9f05e025b5138c9db85d90a41b03ad9"), let content = p.content {
            let images = getImgUrlsFromContent(content)
            if let first = images.first {
                let galleryItem = GalleryItem(url: first, event: p)
                FullImageViewer(fullImageURL: first, galleryItem: galleryItem, mediaPostPreview: $mediaPostPreview, sharableImage: $sharableImage, sharableGif: $sharableGif)
            }
            else {
                Text(verbatim: "no image")
            }
        }
        else {
            Text(verbatim: "eeuh")
        }
    }
}



