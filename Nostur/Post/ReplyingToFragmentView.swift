//
//  ReplyingToFragment.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/01/2023.
//

import SwiftUI
import Combine

struct ReplyingToFragmentView: View {
    
    @ObservedObject var nrPost:NRPost
    
    var body: some View {
        Group {
            if let rendered = nrPost.replyingToUsernamesMarkDown {
                Text(rendered)
                        .fontWeight(.light)
                        .foregroundColor(.secondary)
//                        .accentColor(Color("AccentColor"))
//                        .tint(Color("AccentColor"))
                        .frame(maxWidth:.infinity, alignment: .leading)
                }
        }
    }
}

struct ReplyingToFragmentView_Previews: PreviewProvider {
    static var previews: some View {
        
        VStack {
            // No replyTo.contact
            let event1 = PreviewFetcher.fetchNRPost("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3")
            
            // With replyTo.contact
            let event2 = PreviewFetcher.fetchNRPost("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e")
            
            // No reply at all.
            let event3 = PreviewFetcher.fetchNRPost("d90c63ca06c0eab08d5c79d3991cd22b6c0e2f4e56167ae918343f2a9bc98ff1")
            
            if (event1 != nil) {
                ReplyingToFragmentView(nrPost: event1!)
                Spacer()
            }
        
            if (event2 != nil) {
                ReplyingToFragmentView(nrPost: event2!)
                Spacer()
            }
            
            if (event3 != nil) {
                ReplyingToFragmentView(nrPost: event3!)
                Spacer()
            }
        }
        .withPreviewEnvironment()
        
    }
}
