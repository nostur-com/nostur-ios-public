//
//  SingleMediaViewer.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/03/2023.
//

import SwiftUI
import NukeUI
import Nuke
//import NukeVideo

struct SingleMediaViewer: View {
    @EnvironmentObject var ns:NosturState // Only needed for `imagesShown`
    let url:URL
    let pubkey:String
    var height:CGFloat?
    let imageWidth:CGFloat
    let isFollowing:Bool
    @State var fullScreenItem:FullScreenItem?
    @State var imagesShown = false
    
    var body: some View {
        VStack {
            if imagesShown {
                if (url.absoluteString.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                    LazyImage(url: url) { state in
                        if let container = state.imageContainer {
                            if container.type == .gif, let gifData = container.data {
                                
                                if let gifSize = getGifDimensions(data: gifData) {
                                    let scaledWidth = imageWidth / gifSize.width
                                    let scaledHeight = gifSize.height * scaledWidth
                                 
                                    AnimatedGifView(gifData: gifData, width: imageWidth, height: scaledHeight, contentMode: .scaleAspectFit)
                                        .frame(width: imageWidth, height: scaledHeight)
                                        .onTapGesture {
                                            sendNotification(.fullScreenView, FullScreenItem(url: url))
                                        }
                                    
                                } else {
                                    Label("Failed to load gif", systemImage: "exclamationmark.triangle.fill")
                                        .centered()
                                }
                            }
                            else if let image = state.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .onTapGesture {
                                        sendNotification(.fullScreenView, FullScreenItem(url: url))
                                    }
                            }
                            else {
                                CenteredProgressView()
                                    .background(Color("LightGray"))
                            }
                        }
                        else {
                            CenteredProgressView()
                                .background(Color("LightGray"))
                        }
                    }
                    .pipeline(ImageProcessing.shared.content) // NO PROCESSING FOR ANIMATED GIF (BREAKS ANIMATION)
                    .priority(.low)
                }
                else {
                    LazyImage(request: ImageRequest(url: url,
                                            processors: [.resize(width: imageWidth, upscale: true)],
                                            userInfo: [.scaleKey: UIScreen.main.scale])) { state in
                        if let image = state.image {
                            image
                                .onTapGesture {
                                    sendNotification(.fullScreenView, FullScreenItem(url: url))
                                }
                        }
                        else if state.error != nil {
                            Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
                                .centered()
                            .frame(height: 250)
                            .background(Color("LightGray"))
                        }
                        else {
                            CenteredProgressView()
                                .frame(height: 250)
                                .background(Color("LightGray"))
                        }
                    }
                                                    .pipeline(ImageProcessing.shared.content) // No processing again here, we probably never show the image again
                }
            }
            else {
                Text("Tap to load media")
                    .centered()
                .frame(height: 200)
                .background(.regularMaterial)
                .cornerRadius(10)
                .onTapGesture {
                    imagesShown = true
                }
            }
        }
        .onAppear {
            imagesShown = !SettingsStore.shared.restrictAutoDownload || isFollowing
        }
    }
    
}

struct SingleMediaViewer_Previews: PreviewProvider {
    static var previews: some View {
        let content1 = "one image: https://nostur.com/screenshots/badges.png dunno"
        
        let urlsFromContent = getImgUrlsFromContent(content1)
        
        SingleMediaViewer(url:urlsFromContent[0],  pubkey: "dunno", imageWidth: UIScreen.main.bounds.width, isFollowing: true)
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
