//
//  FooterFragmentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2023.
//

import SwiftUI

struct FooterFragmentView: View {
    @EnvironmentObject var theme:Theme
    let nrPost:NRPost
    var isDetail = false
    
    init(nrPost: NRPost, isDetail: Bool = false) {
        self.nrPost = nrPost
        self.isDetail = isDetail
    }
    
    var body: some View {
//        #if DEBUG
//        let _ = Self._printChanges()
//        #endif
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                // REPLY
                ReplyButton(nrPost: nrPost, isDetail: isDetail)
                Spacer()
                
                // REPOST
                RepostButton(nrPost: nrPost)
                Spacer()
                
                // LIKE
                LikeButton(nrPost: nrPost)
                Spacer()
                
                // ZAP
                if !IS_APPLE_TYRANNY {
                    ZapButton(nrPost: nrPost)
                        .opacity(nrPost.contact?.anyLud ?? false ? 1 : 0.3)
                        .disabled(!(nrPost.contact?.anyLud ?? false))
                    Spacer()
                }
                
                // BOOKMARK
                BookmarkButton(nrPost: nrPost)
                
            }
            .frame(height: 28)

            // UNDO SEND AND SENT TO RELAYS
            OwnPostFooter(nrPost: nrPost)
        }
        .foregroundColor(theme.footerButtons)
        .font(.system(size: 14))        
    }
}


struct PreviewFooterFragmentView: View {
    
    @EnvironmentObject var theme:Theme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack {
                    Image("ReplyIcon")
                    Text("0").opacity(0)
                }
                .padding([.vertical, .trailing], 5)
                Spacer()
                
                // REPOST
                HStack {
                    Image("RepostedIcon")
                    Text("0").opacity(0)
                }
                .padding(5)
                Spacer()
                
                // LIKE
                HStack {
                    Image("LikeIcon")
                    Text("0").opacity(0)
                }
                .padding(5)
                Spacer()
                
                
                Image("BoltIcon")
                Text("0").opacity(0)
                Spacer()
                
                
                Image("BookmarkIcon")
                    .padding(.vertical, 5)
                    .padding(.leading, 10)
//                    .padding(.trailing, 5)
                
            }
        }
        .foregroundColor(theme.footerButtons)
        .font(.system(size: 14))
        
        
    }
}

struct FooterFragmentView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadPosts()
        }) {
            VStack(spacing: 0) {
                
                PreviewFooterFragmentView()
                
                if let p = PreviewFetcher.fetchNRPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0") {
                    FooterFragmentView(nrPost: p)
                }
            }
//            .padding(.horizontal, 20)
        }
    }
}



