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
    
    let url:URL
    var height:CGFloat?
    @State var fullScreenItem:FullScreenItem?
    
    var body: some View {
        if (url.absoluteString.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
            GeometryReader { geo in
                LazyImage(url: url) { state in
                    if let container = state.imageContainer {
                        if container.type == .gif, let gifData = container.data {
                            AnimatedGifView(gifData: gifData, width: geo.size.width, height: geo.size.height, contentMode: .scaleAspectFit)
//                                        .scaledToFill()
//                                        .clipped()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .onTapGesture {
                                    sendNotification(.fullScreenView, FullScreenItem(url: url))
                                }
                        }
                        else if let image = state.image {
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
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
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        else {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .scaledToFit()
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
    
}

struct SingleMediaViewer_Previews: PreviewProvider {
    static var previews: some View {
        let content1 = "one image: https://nostur.com/screenshots/badges.png dunno"
        
        let urlsFromContent = getImgUrlsFromContent(content1)
        
        SingleMediaViewer(url:urlsFromContent[0])
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
