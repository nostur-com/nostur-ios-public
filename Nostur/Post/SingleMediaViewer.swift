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
    @State var fullScreenItem:FullScreenItem?
    @State var imagesShown = false
    
    var body: some View {
        VStack {
            if imagesShown {
                if (url.absoluteString.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                    LazyImage(url: url) { state in
                        if let container = state.imageContainer {
                            if container.type == .gif, let gifData = container.data {
                                GeometryReader { geo in
                                    AnimatedGifView(gifData: gifData, width: geo.size.width, height: geo.size.height, contentMode: .scaleAspectFit)
                                    //                                    .scaledToFill()
                                    //                                    .clipped()
                                        .frame(width: geo.size.width, height: geo.size.height)
                                        .onTapGesture {
                                            sendNotification(.fullScreenView, FullScreenItem(url: url))
                                        }
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
                        else {
                            CenteredProgressView()
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
            imagesShown = !SettingsStore.shared.restrictAutoDownload || ns.isFollowing(pubkey)
        }
    }
    
}

struct SingleMediaViewer_Previews: PreviewProvider {
    static var previews: some View {
        let content1 = "one image: https://nostur.com/screenshots/badges.png dunno"
        
        let urlsFromContent = getImgUrlsFromContent(content1)
        
        SingleMediaViewer(url:urlsFromContent[0],  pubkey: "dunno", imageWidth: UIScreen.main.bounds.width)
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
