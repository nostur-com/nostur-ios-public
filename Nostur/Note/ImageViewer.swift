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

struct ImageViewer: View {
    @EnvironmentObject var ns:NosturState // Only needed for `eventIsRestricted`
    let imgUrls:[URL]
    let pubkey:String
    
    @State var fullScreenItem:FullScreenItem?
    @State var imagesShown = false
    
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
                                        VideoPlayerView(videoURL: imgUrls[index])
                                    }
                                    else if (imgUrls[index].absoluteString.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                                        LazyImage(url: imgUrls[index]) { state in
                                            if let container = state.imageContainer {
                                                if container.type == .gif, let gifData = container.data {
                                                    AnimatedGifView(gifData: gifData, width: side, height: 200, contentMode: .scaleAspectFit)
                                                        .frame(width: side, height: 200)
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
                        if ([".mp4",".mov"].contains(imgUrls.first?.absoluteString.suffix(4))) {
                            VideoPlayerView(videoURL: imgUrls.first!)
                        }
                        else if (imgUrls.first?.absoluteString.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                            LazyImage(url: imgUrls.first!) { state in
                                if let container = state.imageContainer {
                                    if container.type == .gif, let gifData = container.data {
                                        AnimatedGifView(gifData: gifData, width: geo.size.width, height: geo.size.height, contentMode: .scaleAspectFit)
                                            .frame(width: geo.size.width, height: geo.size.height)
                                            .onTapGesture {
                                                fullScreenItem = FullScreenItem(url: imgUrls.first!)
                                            }
                                    }
                                    else if let image = state.image {
                                        image
                                            .resizable()
                                            .scaledToFit()
                                            .onTapGesture {
                                                fullScreenItem = FullScreenItem(url: imgUrls.first!)
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
                            LazyImage(url: imgUrls.first!) { state in
                                if let image = state.image {
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .onTapGesture {
                                            fullScreenItem = FullScreenItem(url: imgUrls.first!)
                                        }
                                }
                                else {
                                    CenteredProgressView()
                                }
                            }
                            .pipeline(ImageProcessing.shared.content) // No processing again here, we probably never show the image again

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
    
    //    var bodyx: some View {
    //        GeometryReader { geometry in
    //            let side = geometry.size.width / 2
    //            let item = GridItem(.fixed(side), spacing: 2)
    //            if (imgUrls_.count > 1) {
    //                LazyVGrid(columns: Array(repeating: item, count: 2), spacing: 2) {
    //                    ForEach(0..<imgUrls_.count, id: \.self) { index in
    //                        LazyImage(url: imgUrls_[index])
    //                            .pipeline(ImageProcessing.shared.content)
    //                            .priority(.low)
    //                            .processors([ImageProcessors.Resize(width: side)])
    //                            .frame(width: side, height: side)
    //                        // TODO: DUNNO MAYBE NEED PREFETCHER SOME DAY
    //                        //                            .onAppear { model.onAppear(index) }
    //                        //                            .onDisappear { model.onDisappear(index) }
    //                            .onTapGesture {
    //                                fullScreenItem = FullScreenItem(url: imgUrls_[index])
    //                            }
    //                    }
    //                }
    //            }
    //            else if (!imgUrls_.isEmpty) {
    ////                Text("WTF")
    //                LazyVGrid(columns: [GridItem(.fixed(geometry.size.width))], spacing: 2) {
    //                    LazyImage(url: imgUrls_[0])
    //
    //                        .pipeline(ImageProcessing.shared.content)
    //                        .priority(.low)
    //                        .processors([ImageProcessors.Resize(width: geometry.size.width)])
    //                        .frame(width: geometry.size.width)
    ////                        .scaledToFit()
    //                        .frame(height: 350)
    //                    // TODO: DUNNO MAYBE NEED PREFETCHER SOME DAY
    //                    //                            .onAppear { model.onAppear(0) }
    //                    //                            .onDisappear { model.onDisappear(0) }
    //                        .onTapGesture {
    //                            fullScreenItem = FullScreenItem(url: imgUrls_[0])
    //                        }
    //                }
    //                .frame(height: 350)
    //
    //            }
    //        }
    //        .onAppear {
    //            imgUrls = getImgUrlsFromContent(content)
    //        }
    //        .fullScreenCover(item: $fullScreenItem, content: { item in
    //            FullImageViewer(fullImageURL:item.url)
    //        })
    //    }
}

struct FullImageViewer: View {
    
    @Environment(\.dismiss) var dismiss
    //    @Binding var fullImageIsShown:Bool
    var fullImageURL:URL
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var position: CGSize = .zero
    @State private var newPosition: CGSize = .zero
    
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
                        .onEnded { value in
                            print(value.translation)
                            switch(value.translation.width, value.translation.height) {
                                    //                    case (...0, -30...30):  print("left swipe")
                                    //                    case (0..., -30...30):  print("right swipe")
                                    //                    case (-100...100, ...0):  print("up swipe")
                                case (-100...100, 0...):  dismiss()
                                default:  print("no clue")
                            }
                        }
                    )
        
        GeometryReader { geo in
            ZStack {
                VStack {
                    if ([".mp4",".mov"].contains(fullImageURL.absoluteString.suffix(4))) {
                        VideoPlayerView(videoURL: fullImageURL)
                    }
                    else if (fullImageURL.absoluteString.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                        LazyImage(url: fullImageURL) { state in
                            if let container = state.imageContainer {
                                if container.type == .gif, let gifData = container.data {
                                    AnimatedGifView(gifData: gifData, width: geo.size.width, height: geo.size.height, contentMode: .scaleAspectFit)
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
                                else {
                                    CenteredProgressView()
                                }
                            }
                            else {
                                CenteredProgressView()
                            }
                        }
                        .pipeline(ImageProcessing.shared.content) // NO PROCESSING FOR ANIMATED GIF (BREAKS ANIMATION)
                        .priority(.high)
                    }
                    else {
                        LazyImage(url: fullImageURL) { state in
                            if let image = state.image {
                                image
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
                            else {
                                CenteredProgressView()
                            }
                        }
    //                                        .processors([.resize(height: 150)])
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
    let regex = try! NSRegularExpression(pattern: "(?i)\\bhttps?:\\/\\/\\S+?\\.(?:mp4|mov|png|jpe?g|gif|webp|bmp)\\b")
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
        
        let content4 = ###"some images: https://nostur.com/screenshots/badges.png https://nostur.com/screenshots/multi-account.jpg https://nostur.com/screenshots/tagging.gif\nhttps://nostur.com/screenshots/zaps-revamped.png https://nostur.com/screenshots/detail-pane-ipad.jpg"###
        
        
        let content1 = "one image: https://nostur.com/screenshots/badges.png dunno"
        
        let urlsFromContent = getImgUrlsFromContent(content1)
        
        List {
            //            LazyImage(url: URL(string: "https://nostur.com/screenshots/badges.png")!)
            //                .frame(height: 200)
            //                .padding(20)
            //                .listRowInsets(EdgeInsets())
            //
            //            ImageViewer(content: content1)
            ImageViewer(imgUrls: urlsFromContent, pubkey: "")
                .listRowInsets(EdgeInsets())
        }
        .listStyle(.inset)
        .withPreviewEnvironment()
    }
}

// TODO: DUNNO MAYBE NEED PREFETCHER SOME DAY
//final class PrefetchDemoViewModel: ObservableObject, ScrollViewPrefetcherDelegate {
//    private let imagePrefetcher: ImagePrefetcher
//    private let scrollViewPrefetcer: ScrollViewPrefetcher
//    let urls: [URL]
//
//    init() {
//        self.imagePrefetcher = ImagePrefetcher()
//        self.scrollViewPrefetcer = ScrollViewPrefetcher()
//        self.urls = imgUrls
//
//        self.scrollViewPrefetcer.delegate = self
//    }
//
//    func onAppear(_ index: Int) {
//        scrollViewPrefetcer.onAppear(index)
//    }
//
//    func onDisappear(_ index: Int) {
//        scrollViewPrefetcer.onDisappear(index)
//    }
//
//    // MARK: ScrollViewPrefetcherDelegate
//    func getAllIndicesForPrefetcher(_ prefetcher: ScrollViewPrefetcher) -> Range<Int> {
//        urls.indices
//    }
//
//    func prefetcher(_ prefetcher: ScrollViewPrefetcher, prefetchItemsAt indices: [Int]) {
//        imagePrefetcher.startPrefetching(with: indices.map { urls[$0] })
//    }
//
//    func prefetcher(_ prefetcher: ScrollViewPrefetcher, cancelPrefechingForItemAt indices: [Int]) {
//        imagePrefetcher.stopPrefetching(with: indices.map { urls[$0] })
//    }
//}
//
//
//// MARK: - ScrollViewPrefetcher
//protocol ScrollViewPrefetcherDelegate: AnyObject {
//    /// Returns all valid indices for the collection.
//    func getAllIndicesForPrefetcher(_ prefetcher: ScrollViewPrefetcher) -> Range<Int>
//    func prefetcher(_ prefetcher: ScrollViewPrefetcher, prefetchItemsAt indices: [Int])
//    func prefetcher(_ prefetcher: ScrollViewPrefetcher, cancelPrefechingForItemAt indices: [Int])
//}
//
//final class ScrollViewPrefetcher {
//    private let prefetchWindowSize: Int
//
//    weak var delegate: ScrollViewPrefetcherDelegate?
//
//    private var visibleIndices: Set<Int> = []
//    private var flushedVisibleIndices: Set<Int> = []
//    private var isRefreshScheduled = false
//    private var prefetchWindow = 0..<0
//
//    init(prefetchWindowSize: Int = 12) {
//        self.prefetchWindowSize = prefetchWindowSize
//    }
//
//    func onAppear(_ index: Int) {
//        visibleIndices.insert(index)
//        scheduleRefreshIfNeeded()
//    }
//
//    func onDisappear(_ index: Int) {
//        visibleIndices.remove(index)
//        scheduleRefreshIfNeeded()
//    }
//
//    /// SwiftUI sometimes calls onAppear in unexpected order, buffer takes care of it.
//    private func scheduleRefreshIfNeeded() {
//        guard !isRefreshScheduled else { return }
//        isRefreshScheduled = true
//        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
//            self?.updatePrefetchWindow()
//        }
//    }
//
//    private func updatePrefetchWindow() {
//        isRefreshScheduled = false
//        guard !visibleIndices.isEmpty else { return } // Should never happen
//        if flushedVisibleIndices.isEmpty {
//            // Showing screen for the first time
//            let lowerBound = visibleIndices.max()! + 1
//            updatePrefetchWindow(lowerBound..<(lowerBound + prefetchWindowSize))
//        } else {
//            // Need to figure out in which direction we the user is scrolling
//            let isScrollingDown = visibleIndices.max()! > flushedVisibleIndices.max()!
//            if isScrollingDown || visibleIndices.contains(0) {
//                let lowerBound = visibleIndices.max()! + 1
//                updatePrefetchWindow(lowerBound..<(lowerBound + prefetchWindowSize))
//            } else {
//                let upperBound = visibleIndices.min()! - 1
//                updatePrefetchWindow((upperBound - prefetchWindowSize)..<upperBound)
//            }
//        }
//
//        flushedVisibleIndices = visibleIndices
//    }
//
//    private func updatePrefetchWindow(_ newPrefetchWindow: Range<Int>) {
//        let oldPrefetchIndices = Set(prefetchWindow)
//        let newPrefetchIndices = Set(newPrefetchWindow)
//
//        prefetchWindow = newPrefetchWindow
//
//        let allIndices = Set(delegate?.getAllIndicesForPrefetcher(self) ?? 0..<0)
//
//        let removedIndicides = oldPrefetchIndices
//            .subtracting(newPrefetchIndices)
//            .intersection(allIndices) // Only call for visible items
//            .sorted()
//        let addedIndices = newPrefetchIndices
//            .subtracting(oldPrefetchIndices)
//            .intersection(allIndices) // Only call for visible items
//            .sorted()
//
//        delegate?.prefetcher(self, prefetchItemsAt: addedIndices)
//        delegate?.prefetcher(self, cancelPrefechingForItemAt: removedIndicides)
//    }
//}
