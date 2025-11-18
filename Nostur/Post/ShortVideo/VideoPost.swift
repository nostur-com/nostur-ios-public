//
//  VideoPost.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/11/2025.
//

import SwiftUI

struct VideoPost: View {
    
    @Environment(\.availableHeight) var availableHeight: CGFloat
    @Environment(\.availableWidth) var availableWidth: CGFloat
    
    let nrPost: NRPost
    let theme: Theme
    
    @State private var isPlaying = false
    
    var body: some View {
        VideoPostLayout(nrPost: nrPost, theme: theme) {
            if let videoURL = nrPost.eventUrl {
                ShortVideoPlayer(url: videoURL, isPlaying: $isPlaying)
                    .frame(width: availableWidth, height: min((availableWidth*3),availableHeight))
                    .background(Color.black)
                    .frame(width: availableWidth, height: availableHeight)
                    .onTapGesture(perform: {
                        isPlaying = true
                    })
                    .onAppear {
        //                isPlaying = true
                    }
                    .onDisappear {
                        isPlaying = false
                    }
            }
        }
    }
}

@available(iOS 26.0, *)
#Preview("Vine") {
    @Previewable @Environment(\.theme) var theme
    @Previewable @State var nrPost = testNRPost(###"{"pubkey":"5943c88f3c60cd9edb125a668e2911ad419fc04e94549ed96a721901dd958372","created_at":1763179480,"kind":22,"tags":[["alt","Vertical Video"],["title",""],["published_at","1763179481"],["imeta","url https://blossom.primal.net/cf5a5ff1dddc3b97d8938f33d1088c9e5babcdc3f94c5178112392e9b3a36d27.mp4","m video/mp4","alt Vertical Video","x cf5a5ff1dddc3b97d8938f33d1088c9e5babcdc3f94c5178112392e9b3a36d27","size 3069605","dim 720x1280","blurhash _FF}~1~p%z-p~W0fE2.S?aNH^+xu%gt79ZIV-WWVNaxu-:IpjG%MNHoMsAR,S6kCX5NxofxZNGf,W.slt7X8bFs:%1WARkxFslR*R*xDV@kDjFnOoft7WBs;t7oKafs;of"],["nonce","229","16"]],"id":"0000c09aa7133e2e75e7e352af918c56e7a8cafc4ed456a67a24dc4a9f777272","content":"Marin 💕✨\nOriginally published in: 2025-11-13","sig":"53badb2a42b0b147252b0ac23545773a50ec123c9761da6e910a7c37f046dccae51e7174d5498ff83e4a33987c9a618808b62d7c34b09abaafec4b543b6ed819"}"###)
    PreviewContainer({ pe in
        
    }) {
        PreviewApp {
            ScrollView {
                LazyVStack {
//                    Color.random
//                        .frame(height: 400)
                    
                    VideoPost(nrPost: nrPost, theme: theme)
                    
//                    Color.random
//                        .frame(height: 400)
//
//                    Color.random
//                        .frame(height: 400)
                }
            }
        }
    }
}
