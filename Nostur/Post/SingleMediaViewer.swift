//
//  SingleMediaViewer.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/03/2023.
//

import SwiftUI
import NukeUI
import Nuke

struct SingleMediaViewer: View {
    
    let url:URL
    @State var fullScreenItem:FullScreenItem?
    
    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image
                    .resizable()
                    .scaledToFit()
                //                                    .aspectRatio(contentMode: .fit)
                //                                    .frame(maxWidth: .infinity)
                //                                    .frame(width: side, height: 200)
                    .onTapGesture {
                        fullScreenItem = FullScreenItem(url: url)
                    }
            }
            else {
                CenteredProgressView()
            }
        }
        .pipeline(ImageProcessing.shared.content) // No processing again here, we probably never show the image again
        .fullScreenCover(item: $fullScreenItem, content: { item in
            FullImageViewer(fullImageURL:item.url)
        })
    }
}

struct SingleMediaViewer_Previews: PreviewProvider {
    static var previews: some View {
        let content1 = "one image: https://nostur.com/screenshots/badges.png dunno"
        
        let urlsFromContent = getImgUrlsFromContent(content1)
        
        SingleMediaViewer(url:urlsFromContent[0])
    }
}
