//
//  ImageViewer.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/03/2023.
//

import SwiftUI
import Nuke
import NukeUI



struct FullScreenItem : Identifiable {
    var url:URL
    var id:String { url.absoluteString }
}

struct ImageViewer: View {
    @EnvironmentObject var ns:NosturState // Only needed for `eventIsRestricted`
    // TODO: DUNNO MAYBE NEED PREFETCHER SOME DAY
//    @StateObject var model = PrefetchDemoViewModel()
//    @State var fullImageIsShown = false
    let imgUrls:[URL]
    let pubkey:String
    
    @State var fullScreenItem:FullScreenItem?
    @State var imagesShown = false
    
    init(content: String, pubkey:String) {
        self.imgUrls = ImageViewer.getImgUrlsFromContent(content)
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
                                ForEach(0..<imgUrls.count, id: \.self) { index in
                                    LazyImage(url: imgUrls[index]) { state in
                                        if let image = state.image {
                                            image.resizingMode(.aspectFit)
                                        }
                                        else {
                                            CenteredProgressView()
                                        }
                                    }
                                    .pipeline(ImageProcessing.shared.postContentPipeline)
                                    .priority(.low)
                                    .processors([ImageProcessors.Resize(width: side)])
                                    .frame(width: side, height: 200)
                                    // TODO: DUNNO MAYBE NEED PREFETCHER SOME DAY
                                    //                            .onAppear { model.onAppear(index) }
                                    //                            .onDisappear { model.onDisappear(index) }
                                    .onTapGesture {
                                        fullScreenItem = FullScreenItem(url: imgUrls[index])
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
                            Text("Tap to load images")
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
                    GeometryReader { geometry in
                        LazyImage(url: imgUrls.first!) { state in
                            if let image = state.image {
                                image.resizingMode(.aspectFit)
                            }
                            else {
                                CenteredProgressView()
                            }
                        }
                        .pipeline(ImageProcessing.shared.postContentPipeline)
                        .priority(.low)
                        .processors([ImageProcessors.Resize(width: geometry.frame(in: .local).size.width)])
                        .onTapGesture {
                            fullScreenItem = FullScreenItem(url: imgUrls.first!)
                        }
                        .fullScreenCover(item: $fullScreenItem, content: { item in
                            FullImageViewer(fullImageURL:item.url)
                        })
                    }
                    .frame(height: 200)
                }
                else {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("Tap to load image")
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
//                            .pipeline(ImageProcessing.shared.postContentPipeline)
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
//                        .pipeline(ImageProcessing.shared.postContentPipeline)
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
    
    static func getImgUrlsFromContent(_ content:String) -> [URL] {
        var urls:[URL] =  []
        let regex = try! NSRegularExpression(pattern: "(?i)\\bhttps?:\\/\\/\\S+?\\.(?:png|jpe?g|gif|webp|bmp)\\b")
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
}

struct FullImageViewer: View {
    
    @Environment(\.dismiss) var dismiss
//    @Binding var fullImageIsShown:Bool
    var fullImageURL:URL
    
    var body: some View {
        ZStack {
            VStack {
                LazyImage(url: fullImageURL) { state in
                    if let image = state.image {
                        image
                            .resizingMode(.aspectFit)
                    }
                    else {
                        CenteredProgressView()
                    }
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
        .gesture(DragGesture(minimumDistance: 3.0, coordinateSpace: .local)
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
    }
}

struct ImageViewer_Previews: PreviewProvider {
    static var previews: some View {
        
        let content4 = ###"some images: https://nostur.com/screenshots/badges.png https://nostur.com/screenshots/multi-account.jpg https://nostur.com/screenshots/tagging.gif\nhttps://nostur.com/screenshots/zaps-revamped.png https://nostur.com/screenshots/detail-pane-ipad.jpg"###
        
        
        let content1 = "one image: https://nostur.com/screenshots/badges.png dunno"
        
        List {
//            LazyImage(url: URL(string: "https://nostur.com/screenshots/badges.png")!)
//                .frame(height: 200)
//                .padding(20)
//                .listRowInsets(EdgeInsets())
//
////            ImageViewer(content: content1)
            ImageViewer(content: content1, pubkey: "")
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
