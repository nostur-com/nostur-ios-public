//
//  ReplyingToFragmentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/01/2023.
//

import SwiftUI
import Combine

struct ReplyingToFragmentView: View {
    @Environment(\.theme) private var theme
    @Environment(\.nxViewingContext) private var nxViewingContext
    private let nrPost: NRPost
    @ObservedObject private var replyingToAttributes: ReplyingToAttributes
    
    init(nrPost: NRPost) {
        self.nrPost = nrPost
        self.replyingToAttributes = nrPost.replyingToAttributes
    }

    var body: some View {
        if let rendered = replyingToAttributes.replyingToUsernamesMarkDown {
            Text(rendered)
                .fontWeight(.light)
                .foregroundColor(theme.secondary)
                .frame(maxWidth:.infinity, alignment: .leading)
                .allowsHitTesting(!nxViewingContext.contains(.preview))
        }
        else {
            EmptyView()
        }
    }
}

struct ReplyingToFragmentView_Previews: PreviewProvider {
    static var previews: some View {
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            VStack {
                // No replyTo.contact
                if let event1 = PreviewFetcher.fetchNRPost("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3") {
                    ReplyingToFragmentView(nrPost: event1)
                }
                
                // With replyTo.contact
                if let event2 = PreviewFetcher.fetchNRPost("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e") {
                    ReplyingToFragmentView(nrPost: event2)
                }
                
                // No reply at all.
                if let event3 = PreviewFetcher.fetchNRPost("d90c63ca06c0eab08d5c79d3991cd22b6c0e2f4e56167ae918343f2a9bc98ff1") {
                    ReplyingToFragmentView(nrPost: event3)
                }
            }
        }
    }
}
