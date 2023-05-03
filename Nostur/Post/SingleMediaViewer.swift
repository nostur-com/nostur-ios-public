//
//  SingleMediaViewer.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/03/2023.
//

import SwiftUI
import NukeUI
import Nuke

@MainActor
struct SingleMediaViewer: View {
    @EnvironmentObject var ns:NosturState // Only needed for `imagesShown`
    let url:URL
    let pubkey:String
    var height:CGFloat?
    let imageWidth:CGFloat
    let isFollowing:Bool
    var fullWidth:Bool = false
    @State var imagesShown = false

    var body: some View {
        VStack {
            if imagesShown {
                makeImage(url: url)
            }
            else {
                Text("Tap to load media")
                   .centered()
                   .frame(height: fullWidth ? 600 : 250)
                   .background(Color("LightGray").opacity(0.2))
                   .highPriorityGesture(
                       TapGesture()
                           .onEnded { _ in
                               imagesShown = true
                           }
                   )
           }
        }
        .onAppear {
            imagesShown = !SettingsStore.shared.restrictAutoDownload || isFollowing
        }
    }

    // This is where the image view is created.
    func makeImage(url: URL) -> some View {
        LazyImage(request: ImageRequest(url: url,
                                        processors: [.resize(width: imageWidth, upscale: true)],
                                        userInfo: [.scaleKey: UIScreen.main.scale])) { state in
            
            if state.error != nil {
                Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
                    .centered()
                    .frame(height: fullWidth ? 600 : 250)
                    .background(Color("LightGray").opacity(0.2))
            }
            else if let container = state.imageContainer, container.type ==  .gif, let data = container.data {
                if fullWidth {
                    GIFImage(data: data)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .onTapGesture {
                            sendNotification(.fullScreenView, FullScreenItem(url: url))
                        }
                }
                else {
                    GIFImage(data: data)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 250)
                        .onTapGesture {
                            sendNotification(.fullScreenView, FullScreenItem(url: url))
                        }
                }
                
            }
            else if let image = state.image {
                if fullWidth {
                    image
                        .onTapGesture {
                            sendNotification(.fullScreenView, FullScreenItem(url: url))
                        }
                }
                else {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(height: 250)
                        .hCentered()
                        .background(Color("LightGray").opacity(0.2))
                        .onTapGesture {
                            sendNotification(.fullScreenView, FullScreenItem(url: url))
                        }
                }
            }
            else if state.isLoading { // does this conflict with showing preview images??
                HStack(spacing: 5) {
                    ProgressView()
                    ImageProgressView(progress: state.progress)
                    Image(systemName: "multiply.circle.fill")
                        .padding(10)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            imagesShown = false
                        }
                }
                .centered()
                .frame(height: fullWidth ? 600 : 250)
                .background(Color("LightGray"))
            }
            else {
                Color("LightGray").opacity(0.2)
            }
        }
        .pipeline(ImageProcessing.shared.content)
    }
}

//struct SingleMediaViewerOld: View {
//    @EnvironmentObject var ns:NosturState // Only needed for `imagesShown`
//    let url:URL
//    let pubkey:String
//    var height:CGFloat?
//    let imageWidth:CGFloat
//    let isFollowing:Bool
//    var fullWidth:Bool = false
//    @State var fullScreenItem:FullScreenItem?
//    @State var imagesShown = false
//    @State var task:AsyncImageTask? = nil
//    @State var imageState:SingleMediaState = .initial
//    @State var percent = 0
//
//    var body: some View {
//        VStack {
//            if imagesShown {
//                LazyImage(r)
//
//
//                if (url.absoluteString.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
//                    LazyImage(url: url) { state in
//                        if let container = state.imageContainer {
//                            if container.type == .gif, let gifData = container.data {
//
//                                if let gifSize = getGifDimensions(data: gifData) {
//                                    let scaledWidth = imageWidth / gifSize.width
//                                    let scaledHeight = gifSize.height * scaledWidth
//
//                                    AnimatedGifView(gifData: gifData, width: imageWidth, height: scaledHeight, contentMode: .scaleAspectFit)
//                                        .frame(width: imageWidth, height: scaledHeight)
//                                        .onTapGesture {
//                                            sendNotification(.fullScreenView, FullScreenItem(url: url))
//                                        }
//
//                                } else {
//                                    Label("Failed to load gif", systemImage: "exclamationmark.triangle.fill")
//                                        .centered()
//                                }
//                            }
//                            else if let image = state.image {
//                                if !fullWidth {
//                                    image
//                                        .resizable()
//                                        .aspectRatio(contentMode: .fit)
//                                        .frame(height:250)
//                                        .onTapGesture {
//                                            sendNotification(.fullScreenView, FullScreenItem(url: url))
//                                        }
//                                }
//                                else {
//                                    image
//                                        .resizable()
//                                        .aspectRatio(contentMode: .fit)
//                                        .onTapGesture {
//                                            sendNotification(.fullScreenView, FullScreenItem(url: url))
//                                        }
//                                }
//                            }
//                            else if state.isLoading {
//                                CenteredProgressView()
//                                    .background(Color("LightGray"))
//                                    .frame(height:250)
//                            }
//                            else {
//                                Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
//                                    .centered()
//                                .frame(height: 250)
//                                .background(Color("LightGray"))
//                            }
//                        }
//                        else {
//                            Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
//                                .centered()
//                            .frame(height: 250)
//                            .background(Color("LightGray"))
//                        }
//                    }
//                    .pipeline(ImageProcessing.shared.content) // NO PROCESSING FOR ANIMATED GIF (BREAKS ANIMATION)
//                    .priority(.low)
//                }
//                else {
//                    LazyImage(request: ) { state in
//                        if let image = state.image {
//                            if !fullWidth {
//                                image
//                                    .resizable()
//                                    .scaledToFit()
//                                    .frame(height:250)
//                                    .onTapGesture {
//                                        sendNotification(.fullScreenView, FullScreenItem(url: url))
//                                    }
//                            }
//                            else {
//                                image
//                                    .onTapGesture {
//                                        sendNotification(.fullScreenView, FullScreenItem(url: url))
//                                    }
//                            }
//                        }
//                        else if state.error != nil {
//                            Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
//                                .centered()
//                            .frame(height: 250)
//                            .background(Color("LightGray"))
//                        }
//                        else {
//                            CenteredProgressView()
//                                .frame(height: 250)
//                                .background(Color("LightGray"))
//                        }
//                    }
//                    .pipeline(ImageProcessing.shared.content) // No processing again here, we probably never show the image again
//                }
//            }
//            else {
//                Text("Tap to load media")
//                    .centered()
//                .frame(height: 250)
//                .background(.regularMaterial)
//                .cornerRadius(10)
//                .onTapGesture {
//                    imagesShown = true
//                }
//            }
//        }
//        .onAppear {
//            imagesShown = !SettingsStore.shared.restrictAutoDownload || isFollowing
//        }
//    }
//
//    func loadImage() async {
//        let url = ImageRequest(url: url,
//                               processors: [.resize(width: imageWidth, upscale: true)],
//                               userInfo: [.scaleKey: UIScreen.main.scale])
//        task = ImageProcessing.shared.content.imageTask(with: url)
//
//        if let task {
//            imageState = .loading
//            for await progress in task.progress {
//                self.percent = Int(ceil(progress.fraction * 100))
//            }
//            if self.percent = 100 {
//                imageState = .loaded
//            }
//        }
//
//        if let response = try? await task?.response {
//            response.
//
//            if response.container.isPreview {
//
//            }
//            else if let type = response.container.type, type == .gif {
//
//            }
//            else {
//
//            }
//
//            if let type = container.type, type.isVideo, let asset = response.container.userInfo[.videoAssetKey] as? AVAsset {
//                self.asset = asset
//                Task {
//                    if let videoSize = await getVideoDimensions(asset: asset) {
//                        self.videoSize = videoSize
//                    }
//                }
//            }
//        }
//
//
////        let imageTask = ImagePipeline.shared.imageTask(with: url)
////
////           imageView.image = try await imageTask.image
////
////        { result in
////
//////        task = ImageProcessing.shared.video.loadImage(with: url) { result in
////            if case let .success(response) = result {
////                if let type = response.container.type, type.isVideo, let asset = response.container.userInfo[.videoAssetKey] as? AVAsset {
////                    self.asset = asset
////                    Task {
////                        if let videoSize = await getVideoDimensions(asset: asset) {
////                            self.videoSize = videoSize
////                        }
////                    }
////                }
////            }
////        }
////
////        if let task {
////            for await progress in task.progress {
////
////            }
////        }
//    }
//
//}

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
            
            SingleMediaViewer(url:urlsFromContent[0],  pubkey: "dunno", imageWidth: UIScreen.main.bounds.width,  isFollowing: true, fullWidth: false)
            
            Button("Clear cache") {
                ImageProcessing.shared.content.cache.removeAll()
            }
        }
    }
}


struct Gif_Previews: PreviewProvider {
    
    static var previews: some View {
        ScrollView {
            LazyVStack {
                if let vPost = PreviewFetcher.fetchVPost("8d49bc0204aad2c0e8bb292b9c99b7dc1bdd6c520a877d908724c27eb5ab8ce8") {
                    NoteRow(vPost: vPost)
                        .boxShadow()
                }
                if let vPost = PreviewFetcher.fetchVPost("1c0ba51ba48e5228e763f72c5c936d610088959fe44535f9c861627287fe8f6d") {
                    NoteRow(vPost: vPost)
                        .boxShadow()
                }
            }
        }
        .background(Color("ListBackground"))
        .withPreviewEnvironment()
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


struct ImageProgressView: View {
    @ObservedObject var progress: FetchImage.Progress

    var body: some View {
        Text("\(Int(ceil(progress.fraction * 100))) %")
    }
}
