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
    let url:URL
    let pubkey:String
    var height:CGFloat?
    let imageWidth:CGFloat
    let isFollowing:Bool
    var fullWidth:Bool = false
    var forceShow = false
    var contentPadding:CGFloat = 10.0
    @State var imagesShown = false
    @State var loadNonHttpsAnyway = false

    var body: some View {
        VStack {
            if url.absoluteString.prefix(7) == "http://" && !loadNonHttpsAnyway {
                VStack {
                    Text("non-https media blocked", comment: "Displayed when an image in a post is blocked")
                    Button(String(localized: "Show anyway", comment: "Button to show the blocked content anyway")) {
                        imagesShown = true
                        loadNonHttpsAnyway = true
                    }
                }
                   .centered()
                   .frame(height: fullWidth ? 600 : 250)
                   .background(Color("LightGray").opacity(0.2))
            }
            else if imagesShown || forceShow {
                LazyImage(request: ImageRequest(url: url,
                                                processors: [.resize(width: imageWidth, upscale: true)],
                                                userInfo: [.scaleKey: UIScreen.main.scale]), transaction: .init(animation: .none)) { state in
                    
                    if state.error != nil {
                        Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
                            .centered()
                            .frame(height: fullWidth ? 600 : 250)
                            .background(Color("LightGray").opacity(0.2))
                            .onAppear {
                                L.og.error("Failed to load image: \(state.error?.localizedDescription ?? "")")
                            }
                    }
                    else if let container = state.imageContainer, container.type ==  .gif, let data = container.data {
                        if fullWidth {
                            GIFImage(data: data)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .onTapGesture {
                                    sendNotification(.fullScreenView, FullScreenItem(url: url))
                                }
                                .padding(.horizontal, -contentPadding)
                        }
                        else {
                            GIFImage(data: data)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 250)
//                                .hCentered()
//                                .background(Color(.secondarySystemBackground))
                                .onTapGesture {
                                    sendNotification(.fullScreenView, FullScreenItem(url: url))
                                }
                        }
                    }
                    else if let image = state.image {
                        VStack(alignment: .center, spacing:0) {
                            if fullWidth {
                                image
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(.horizontal, -contentPadding)
                                    .onTapGesture {
                                        sendNotification(.fullScreenView, FullScreenItem(url: url))
                                    }
                            }
                            else {
                                image
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
//                                    .background(.green)
                                    .frame(height: 250)
//                                    .background(.red)
                                    .hCentered()
//                                    .hCentered()
//                                    .background(Color(.secondarySystemBackground))
                                    .onTapGesture {
                                        sendNotification(.fullScreenView, FullScreenItem(url: url))
                                    }
                            }
                        }
                        .overlay(alignment:.topLeading) {
                            if state.isLoading { // does this conflict with showing preview images??
                                HStack(spacing: 5) {
                                    ImageProgressView(progress: state.progress)
                                    Text("Loading...")
                                }
                            }
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
                        .frame(height: fullWidth ? 600 : 250)
                    }
                    else {
                        Color(.secondarySystemBackground)
                            .frame(height: fullWidth ? 600 : 250)
                    }
                }
                .pipeline(ImageProcessing.shared.content)
            }
            else {
                Text("Tap to load media", comment: "An image placeholder the user can tap to load media (usually an image or gif)")
                   .centered()
                   .frame(height: fullWidth ? 600 : 250)
//                   .background(Color(.secondarySystemBackground))
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
            
            SingleMediaViewer(url:urlsFromContent[0],  pubkey: "dunno", imageWidth: UIScreen.main.bounds.width,  isFollowing: true, fullWidth: false)
            
            Button("Clear cache") {
                ImageProcessing.shared.content.cache.removeAll()
            }
        }
    }
}


struct Gif_Previews: PreviewProvider {
    
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadMedia()
        }) {
            ScrollView {
                LazyVStack {
                    if let nrPost = PreviewFetcher.fetchNRPost("8d49bc0204aad2c0e8bb292b9c99b7dc1bdd6c520a877d908724c27eb5ab8ce8") {
                        PostRowDeletable(nrPost: nrPost)
                            .boxShadow()
                    }
                    if let nrPost = PreviewFetcher.fetchNRPost("1c0ba51ba48e5228e763f72c5c936d610088959fe44535f9c861627287fe8f6d") {
                        PostRowDeletable(nrPost: nrPost)
                            .boxShadow()
                    }
                }
            }
            .background(Color("ListBackground"))
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


struct ImageProgressView: View {
    @ObservedObject var progress: FetchImage.Progress

    var body: some View {
        ProgressView()
        if (progress.fraction != 0) {
            Text(Int(ceil(progress.fraction * 100)), format: .percent)
        }
    }
}
