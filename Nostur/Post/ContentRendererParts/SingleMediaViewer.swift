////
////  SingleMediaViewer.swift
////  Nostur
////
////  Created by Fabian Lachman on 06/03/2023.
////
//
//import SwiftUI
//import NukeUI
//import Nuke
//
//struct SingleMediaViewer: View {
//    @EnvironmentObject private var dim:DIMENSIONS
//    @Environment(\.openURL) private var openURL
//    public let url: URL
//    public let pubkey:String
//    public var height:CGFloat?
//    public let imageWidth:CGFloat
//    public var fullWidth:Bool = false
//    public var autoload = false
//    public var contentPadding:CGFloat = 0.0
//    public var contentMode:ImageProcessingOptions.ContentMode = .aspectFit
//    public var upscale = false
//    public var theme = Themes.default.theme
//    public var scaledDimensions: CGSize? = nil
//    public var imageUrls: [URL]? = nil
//    public var tapUrl: URL?
//    
//    @State private var imagesShown = false
//    @State private var loadNonHttpsAnyway = false
//    @State private var theHeight = DIMENSIONS.MAX_MEDIA_ROW_HEIGHT
//    @State private var isPlaying = false
//    @State private var cancelled = false
//    @State private var retryId = UUID()
//    @State private var theDimensions: CGSize?
//    @State private var overrideLowDataMode = false
//    
//    var body: some View {
////        #if DEBUG
////        let _ = Self._printChanges()
////        #endif
//        if url.absoluteString.prefix(7) == "http://" && !loadNonHttpsAnyway {
//            VStack {
//                Text("non-https media blocked", comment: "Displayed when an image in a post is blocked")
//                    .frame(maxWidth: .infinity, alignment:.center)
//                Button(String(localized: "Show anyway", comment: "Button to show the blocked content anyway")) {
//                    imagesShown = true
//                    loadNonHttpsAnyway = true
//                }
//            }
//            .padding(10)
////            .frame(height: height ?? DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
//            .background(theme.lineColor.opacity(0.2))
//        }
//        else if !cancelled && (autoload || imagesShown) {
//            LazyImage(request: makeImageRequest(url, label: "SingleMediaViewer", overrideLowDataMode: overrideLowDataMode)) { state in
//                if state.error != nil {
//                    if SettingsStore.shared.lowDataMode {
//                        Text(tapUrl?.absoluteString ?? url.absoluteString)
//                            .foregroundColor(theme.accent)
//                            .truncationMode(.middle)
//                            .onTapGesture {
//                                overrideLowDataMode = true
//                            }
//                            .padding(.horizontal, fullWidth ? 10 : 0)
//                    }
//                    else {
//                        VStack {
//                            Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
//                            Button("Retry") { retryId = UUID() }
//                        }
//                            .centered()
//    //                        .frame(height: theHeight)
//                            .background(theme.lineColor.opacity(0.2))
//                            .onAppear {
//                                L.og.error("Failed to load image: \(state.error?.localizedDescription ?? "")")
//                            }
//                    }
//                }
//                else if !dim.isScreenshot, let container = state.imageContainer, container.type == .gif, let data = container.data {
//                    if let dimensions = theDimensions {
//                        let scaledDimensions = Nostur.scaledToFit(dimensions, scale: 1, maxWidth: imageWidth, maxHeight: theHeight)
//                        if fullWidth {
//                            GIFImage(data: data, isPlaying: $isPlaying)
//                            //                            .frame(minHeight: DIMENSIONS.MIN_MEDIA_ROW_HEIGHT)
//                            //                            .resizable()
//                                .aspectRatio(contentMode: .fit)
//                                .frame(height: scaledDimensions.height)
//                                .contentShape(Rectangle())
//                                .onTapGesture {
//                                    if let tapUrl {
//                                        openURL(tapUrl)
//                                        return
//                                    }
//                                    if let imageUrls, imageUrls.count > 1, #available(iOS 17, *) {
//                                        let items: [GalleryItem] = imageUrls.map { GalleryItem(url: $0) }
//                                        let index: Int = imageUrls.firstIndex(of: url) ?? 0
//                                        sendNotification(.fullScreenView17, FullScreenItem17(items: items, index: index))
//                                    }
//                                    else {
//                                        sendNotification(.fullScreenView, FullScreenItem(url: url))
//                                    }
//                                }
//                                .padding(.horizontal, -contentPadding)
//                            //                            .transaction { t in t.animation = nil }
//                            //                            .withoutAnimation()
//                                .task(id: url.absoluteString) {
//                                    do {
//                                        try await Task.sleep(nanoseconds: UInt64(0.75) * NSEC_PER_SEC)
//                                        isPlaying = true
//                                    }
//                                    catch { }
//                                }
//                                .onDisappear {
//                                    isPlaying = false
//                                }
//                            //                            .withoutAnimation()
//    #if DEBUG
//                            //                            .opacity(0.25)
//                            //                            .debugDimensions("GIFImage.fullWidth")
//    #endif
//                        }
//                        else {
//                            GIFImage(data: data, isPlaying: $isPlaying)
//                                .aspectRatio(contentMode: .fit)
//                            //                            .frame(minHeight: DIMENSIONS.MIN_MEDIA_ROW_HEIGHT)
//                            //                            .frame(height: theHeight)
//                            //                            .transaction { t in t.animation = nil }
//                            //                            .background(Color.green)
//                            //                            .withoutAnimation()
//                                .frame(height: scaledDimensions.height)
//                                .contentShape(Rectangle())
//                                .onTapGesture {
//                                    if let tapUrl {
//                                        openURL(tapUrl)
//                                        return
//                                    }
//                                    if let imageUrls, imageUrls.count > 1, #available(iOS 17, *) {
//                                        let items: [GalleryItem] = imageUrls.map { GalleryItem(url: $0) }
//                                        let index: Int = imageUrls.firstIndex(of: url) ?? 0
//                                        sendNotification(.fullScreenView17, FullScreenItem17(items: items, index: index))
//                                    }
//                                    else {
//                                        sendNotification(.fullScreenView, FullScreenItem(url: url))
//                                    }
//                                }
//                                .task(id: url.absoluteString) {
//                                    do {
//                                        try await Task.sleep(nanoseconds: UInt64(0.75) * NSEC_PER_SEC)
//                                        isPlaying = true
//                                    }
//                                    catch { }
//                                }
//                                .onDisappear {
//                                    isPlaying = false
//                                }
//    #if DEBUG
////                                                        .opacity(0.25)
////                                                        .debugDimensions("GIFImage")
//    #endif
//                        }
//                    }
//                    else {
//                        ProgressView()
//                            .onAppear {
//                                DispatchQueue.global().async {
//                                    let theDimensions = getGifDimensions(data: data)
//                                    DispatchQueue.main.async {
//                                        self.theDimensions = theDimensions
//                                    }
//                                }
//                                
//                            }
//                    }
//                }
//                else if let image = state.image {
//                    if fullWidth {
//                        image
//                            .resizable() // <-- without this STILL sometimes a randomly an image with wrong size, even though we have all the correct dimensions. Somewhere Nuke is doing something wrong
////                            .interpolation(.none)
//                            .scaledToFill()
////                            .frame(width: (scaledDimensions?.width ?? imageWidth) >= imageWidth ? imageWidth : (scaledDimensions?.width ?? imageWidth))
////                            .fixedSize()
//                            .padding(.horizontal, -contentPadding)
//                            .onTapGesture {
//                                if let tapUrl {
//                                    openURL(tapUrl)
//                                    return
//                                }
//                                if let imageUrls, imageUrls.count > 1, #available(iOS 17, *) {
//                                    let items: [GalleryItem] = imageUrls.map { GalleryItem(url: $0) }
//                                    let index: Int = imageUrls.firstIndex(of: url) ?? 0
//                                    sendNotification(.fullScreenView17, FullScreenItem17(items: items, index: index))
//                                }
//                                else {
//                                    sendNotification(.fullScreenView, FullScreenItem(url: url))
//                                }
//                            }
////                            .transaction { t in t.animation = nil }
////                            .withoutAnimation()
//                            .overlay(alignment:.topLeading) {
//                                if state.isLoading { // does this conflict with showing preview images??
//                                    ImageProgressView(state: state)
//                                }
//                            }
//#if DEBUG
////                            .opacity(0.25)
////                            .debugDimensions("image.fullWidth")
//#endif
//                    }
//                    else {
//                        image
////                            .interpolation(.none)
//                            .resizable() // <-- without this STILL sometimes a randomly an image with wrong size, even though we have all the correct dimensions. Somewhere Nuke is doing something wrong
//                            .scaledToFit()
//                            .frame(minHeight: 100, maxHeight: theHeight)
//                            .frame(maxWidth: .infinity, alignment: .center)
//                            .onTapGesture {
//                                if let tapUrl {
//                                    openURL(tapUrl)
//                                    return
//                                }
//                                if let imageUrls, imageUrls.count > 1, #available(iOS 17, *) {
//                                    let items: [GalleryItem] = imageUrls.map { GalleryItem(url: $0) }
//                                    let index: Int = imageUrls.firstIndex(of: url) ?? 0
//                                    sendNotification(.fullScreenView17, FullScreenItem17(items: items, index: index))
//                                }
//                                else {
//                                    sendNotification(.fullScreenView, FullScreenItem(url: url))
//                                }
//                            }
////                            .transaction { t in t.animation = nil }
////                            .withoutAnimation()
//                            .overlay(alignment:.topLeading) {
//                                if state.isLoading { // does this conflict with showing preview images??
//                                    ImageProgressView(state: state)
//                                }
//                            }
//#if DEBUG
////                            .opacity(0.25)
////                            .debugDimensions("image")
//#endif
//                    }
//                }
//                else if state.isLoading { // does this conflict with showing preview images??
//                    HStack(spacing: 5) {
//                        ProgressView()
//                        ImageProgressView(state: state)
//                            .frame(width: 48)
//                        Image(systemName: "multiply.circle.fill")
//                            .padding(10)
//                            .contentShape(Rectangle())
//                            .onTapGesture {
//                                imagesShown = false
//                                cancelled = true
//                            }
//                    }
////                    .centered()
//                    .frame(minHeight: 100, maxHeight: theHeight)
////                    .background(Color.red)
////                    .withoutAnimation()
//#if DEBUG
////                    .opacity(0.25)
////                    .debugDimensions("loading")
//#endif
//                }
//                else {
//                    Color(.secondarySystemBackground)
////                        .frame(height: theHeight)
//                        .frame(minHeight: 100, maxHeight: theHeight)
////                        .background(Color.white)
////                        .transaction { t in t.animation = nil }
////                        .withoutAnimation()
//                }
//            }
//            .pipeline(ImageProcessing.shared.content)
//            .id(retryId)
//            .onAppear {
//                if let height = height {
//                    theHeight = max(100, height)
//                }
//            }
////            .transaction { t in t.animation = nil }
//        }
//        else {
//            Text("Tap to load media", comment: "An image placeholder the user can tap to load media (usually an image or gif)")
//                .frame(maxWidth: .infinity, alignment: .center)
//                .padding(10)
//                .background(theme.lineColor.opacity(0.2))
//                .highPriorityGesture(
//                   TapGesture()
//                       .onEnded { _ in
//                           imagesShown = true
//                           cancelled = false
//                       }
//                )
//        }
//    }
//}
//
//enum SingleMediaState {
//    case initial
//    case loading
//    case loaded
//    case error
//}
//
//struct SingleMediaViewer_Previews: PreviewProvider {
//    static var previews: some View {
//        VStack {
//            
////            let content1 = "one image: https://nostur.com/screenshots/badges.png dunno"
////            let content1 = "one image: https://nostur.com/screenshots/lightning-invoices.png dunno"
//            let content1 = "one image: https://media.tenor.com/8ZwnfDCNcUoAAAAC/doctor-dr.gif dunno"
//            
//            let urlsFromContent = getImgUrlsFromContent(content1)
//            
//            SingleMediaViewer(url:urlsFromContent[0],  pubkey: "dunno", imageWidth: UIScreen.main.bounds.width, fullWidth: false, autoload: true, imageUrls: [])
//            
//            Button("Clear cache") {
//                ImageProcessing.shared.content.cache.removeAll()
//            }
//        }
//        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
//        .environmentObject(Themes.default)
//        .environmentObject(DIMENSIONS.shared)
//    }
//}
//
//
//struct Gif_Previews: PreviewProvider {
//    
//    static var previews: some View {
//        PreviewContainer({ pe in
//            pe.loadMedia()
//        }) {
//            PreviewFeed {
//                if let nrPost = PreviewFetcher.fetchNRPost("8d49bc0204aad2c0e8bb292b9c99b7dc1bdd6c520a877d908724c27eb5ab8ce8") {
//                    Box {
//                        PostRowDeletable(nrPost: nrPost)
//                    }
//                      
//                }
//                if let nrPost = PreviewFetcher.fetchNRPost("1c0ba51ba48e5228e763f72c5c936d610088959fe44535f9c861627287fe8f6d") {
//                    Box {
//                        PostRowDeletable(nrPost: nrPost)
//                    }
//                }
//            }
//        }
//    }
//}
//
//
//func getGifDimensions(data: Data) -> CGSize? {
//    // Create a CGImageSource with the Data
//    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
//        return nil
//    }
//
//    // Get the properties of the first image in the animated GIF
//    guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
//          let width = properties[kCGImagePropertyPixelWidth] as? Int,
//          let height = properties[kCGImagePropertyPixelHeight] as? Int else {
//        return nil
//    }
//
//    return CGSize(width: width, height: height)
//}
//
//import Combine
//
//struct ImageProgressView: View {
//    public let state: LazyImageState
//    public var numericOnly = false
//    
//    @State var percent: Int = 0
////    @State var subscriptions = Set<AnyCancellable>()
//
//    var body: some View {
//        if !numericOnly && percent == 0 {
//            Image(systemName: "hourglass.tophalf.filled")
//                .onReceive(state.progress.objectWillChange, perform: { _ in
//                    if Int(state.progress.fraction * 100) % 3 == 0 {
//                        if Int(ceil(state.progress.fraction * 100)) != percent {
//                            percent = Int(ceil(state.progress.fraction * 100))
//                        }
//                    }
//                })
////                .task {
////                    state.progress.objectWillChange
////                        .sink { _ in
////                            if Int(state.progress.fraction * 100) % 3 == 0 {
////                                if Int(ceil(state.progress.fraction * 100)) != percent {
////                                    percent = Int(ceil(state.progress.fraction * 100))
////                                }
////                            }
////                        }
////                        .store(in: &subscriptions)
////                }
//        }
//        else { // not numeric only and not 0
//            Text(percent, format: .percent)
//        }
//    }
//}
