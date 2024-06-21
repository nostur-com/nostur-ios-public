//
//  VideoPreviews.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/06/2024.
//

import SwiftUI

struct VideoPreviews: View {
    @Binding var pastedVideos: [PostedVideoMeta]
    
    var body: some View {
        HStack {
            ForEach(pastedVideos.indices, id:\.self) { index in
                VideoPreviewThumnail(video: pastedVideos[index])
                    .overlay(
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.black)
                            .background(Circle().foregroundColor(.white))
                            .frame(width: 20, height: 20)
                            .padding(5)
                            .onTapGesture {
                                _ = pastedVideos.remove(at: index)
                                L.og.debug("remove: \(index)")
                            },
                        alignment: .topTrailing
                    )
            }
        }
    }
}

struct VideoPreviewThumnail: View {
    @ObservedObject public var video: PostedVideoMeta
    
    var body: some View {
        if let thumbnail = video.thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFit()
        }
        else {
            Image(systemName: "hourglass.tophalf.filled")
                .centered()
        }
    }
}
