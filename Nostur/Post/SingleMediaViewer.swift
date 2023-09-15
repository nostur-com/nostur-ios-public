//
//  SingleMediaViewer.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/03/2023.
//

import SwiftUI
import NukeUI
import Nuke

struct SingleMediaViewer: View {
    @EnvironmentObject var theme:Theme
    let url:URL
    let pubkey:String
    var height:CGFloat?
    let imageWidth:CGFloat
    var fullWidth:Bool = false
    var autoload = false
    var contentPadding:CGFloat = 0.0
    var contentMode:ImageProcessingOptions.ContentMode = .aspectFit
    var upscale = false
    
    @State var imagesShown = false
    @State var loadNonHttpsAnyway = false

    var body: some View {
        if url.absoluteString.prefix(7) == "http://" && !loadNonHttpsAnyway {
            VStack {
                Text("non-https media blocked", comment: "Displayed when an image in a post is blocked")
                    .frame(maxWidth: .infinity, alignment:.center)
                Button(String(localized: "Show anyway", comment: "Button to show the blocked content anyway")) {
                    imagesShown = true
                    loadNonHttpsAnyway = true
                }
            }
            .padding(10)
            .frame(height: height ?? DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
            .background(theme.lineColor.opacity(0.2))
        }
        else if autoload || imagesShown {
            LazyImage(request: makeImageRequest(url, width: imageWidth, height: height, contentMode: contentMode, upscale: upscale, label: "SingleMediaViewer")) { state in
                if state.error != nil {
                    Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
                        .centered()
                        .frame(height: height ?? DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                        .background(theme.lineColor.opacity(0.2))
                        .onAppear {
                            L.og.error("Failed to load image: \(state.error?.localizedDescription ?? "")")
                        }
                }
                else if let container = state.imageContainer, container.type ==  .gif, let data = container.data {
                    if fullWidth {
                        GIFImage(data: data)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(minHeight: DIMENSIONS.MIN_MEDIA_ROW_HEIGHT)
                            .onTapGesture {
                                sendNotification(.fullScreenView, FullScreenItem(url: url))
                            }
                            .padding(.horizontal, -contentPadding)
                            .transaction { t in t.animation = nil }
#if DEBUG
//                            .opacity(0.25)
//                            .debugDimensions("GIFImage.fullWidth")
#endif
                    }
                    else {
                        GIFImage(data: data)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(minHeight: DIMENSIONS.MIN_MEDIA_ROW_HEIGHT)
                            .onTapGesture {
                                sendNotification(.fullScreenView, FullScreenItem(url: url))
                            }
                            .transaction { t in t.animation = nil }
#if DEBUG
//                            .opacity(0.25)
//                            .debugDimensions("GIFImage")
#endif
                    }
                }
                else if let image = state.image {
                    if fullWidth {
                        image
                            .resizable() // <-- without this STILL sometimes a randomly an image with wrong size, even though we have all the correct dimensions. Somewhere Nuke is doing something wrong
//                            .interpolation(.none)
                            .scaledToFit()
                            .padding(.horizontal, -contentPadding)
                            .onTapGesture {
                                sendNotification(.fullScreenView, FullScreenItem(url: url))
                            }
                            .transaction { t in t.animation = nil }
                            .overlay(alignment:.topLeading) {
                                if state.isLoading { // does this conflict with showing preview images??
                                    HStack(spacing: 5) {
                                        ImageProgressView(progress: state.progress)
                                        Text("Loading...")
                                    }
                                }
                            }
#if DEBUG
//                            .opacity(0.25)
//                            .debugDimensions("image.fullWidth")
#endif
                    }
                    else {
                        image
//                            .interpolation(.none)
                            .resizable() // <-- without this STILL sometimes a randomly an image with wrong size, even though we have all the correct dimensions. Somewhere Nuke is doing something wrong
                            .scaledToFit()
                            
                            .onTapGesture {
                                sendNotification(.fullScreenView, FullScreenItem(url: url))
                            }
                            .transaction { t in t.animation = nil }
                            .overlay(alignment:.topLeading) {
                                if state.isLoading { // does this conflict with showing preview images??
                                    HStack(spacing: 5) {
                                        ImageProgressView(progress: state.progress)
                                        Text("Loading...")
                                    }
                                }
                            }
#if DEBUG
//                            .opacity(0.25)
//                            .debugDimensions("image")
#endif
                    }
                }
                else if state.isLoading { // does this conflict with showing preview images??
                    HStack(spacing: 5) {
                        ImageProgressView(progress: state.progress)
                        Image(systemName: "multiply.circle.fill")
                            .padding(10)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                imagesShown = false
                            }
                    }
                    .centered()
                    .frame(height: height ?? DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
#if DEBUG
//                    .opacity(0.25)
//                    .debugDimensions("loading")
#endif
                }
                else {
                    Color(.secondarySystemBackground)
                        .frame(height: height ?? DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                }
            }
            .pipeline(ImageProcessing.shared.content)
            .transaction { t in t.animation = nil }
        }
        else {
            Text("Tap to load media", comment: "An image placeholder the user can tap to load media (usually an image or gif)")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(10)
                .background(theme.lineColor.opacity(0.2))
                .highPriorityGesture(
                   TapGesture()
                       .onEnded { _ in
                           imagesShown = true
                       }
                )
        }
    }
}

enum SingleMediaState {
    case initial
    case loading
    case loaded
    case error
}

struct SingleMediaViewer_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            
//            let content1 = "one image: https://nostur.com/screenshots/badges.png dunno"
//            let content1 = "one image: https://nostur.com/screenshots/lightning-invoices.png dunno"
            let content1 = "one image: https://media.tenor.com/8ZwnfDCNcUoAAAAC/doctor-dr.gif dunno"
            
            let urlsFromContent = getImgUrlsFromContent(content1)
            
            SingleMediaViewer(url:urlsFromContent[0],  pubkey: "dunno", imageWidth: UIScreen.main.bounds.width, fullWidth: false, autoload: true)
            
            Button("Clear cache") {
                ImageProcessing.shared.content.cache.removeAll()
            }
        }
        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}


struct Gif_Previews: PreviewProvider {
    
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadMedia()
        }) {
            SmoothListMock {
                if let nrPost = PreviewFetcher.fetchNRPost("8d49bc0204aad2c0e8bb292b9c99b7dc1bdd6c520a877d908724c27eb5ab8ce8") {
                    Box {
                        PostRowDeletable(nrPost: nrPost)
                    }
                      
                }
                if let nrPost = PreviewFetcher.fetchNRPost("1c0ba51ba48e5228e763f72c5c936d610088959fe44535f9c861627287fe8f6d") {
                    Box {
                        PostRowDeletable(nrPost: nrPost)
                    }
                }
            }
        }
    }
}


func getGifDimensions(data: Data) -> CGSize? {
    // Create a CGImageSource with the Data
    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
        return nil
    }

    // Get the properties of the first image in the animated GIF
    guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else {
        return nil
    }

    return CGSize(width: width, height: height)
}

import Combine

struct ImageProgressView: View {
    let progress: FetchImage.Progress
    @State var percent:Int = 0
    @State var subscriptions = Set<AnyCancellable>()

    var body: some View {
        ProgressView()
            .onAppear {
                progress.objectWillChange
                    .sink { _ in
                        if Int(progress.fraction * 100) % 3 == 0 {
                            if Int(ceil(progress.fraction * 100)) != percent {
                                percent = Int(ceil(progress.fraction * 100))
                            }
                        }
                    }
                    .store(in: &subscriptions)
            }
        if (percent != 0) {
            Text(percent, format: .percent)
        }
    }
}

// Use this function to make sure the image request is same in SingleImageViewer, SmoothList prefetch and SmoothList cancel prefetch.
// else Nuke will prefetch wrong request
func makeImageRequest(_ url:URL, width:CGFloat, height:CGFloat? = nil, contentMode:ImageProcessingOptions.ContentMode = .aspectFit, upscale:Bool = false, label:String = "") -> ImageRequest {
//    L.og.debug("ImageRequest: \(url.absoluteString), \(width) x \(height ?? -1) \(label)")
    return ImageRequest(url: url,
                 processors: [
                    height != nil
                    ? .resize(size: CGSize(width: width, height: height!), contentMode: contentMode, upscale: upscale)
                    : .resize(width: width, upscale: upscale)
                 ],
                userInfo: [.scaleKey: UIScreen.main.scale]
    )
}
