//
//  QuotedNoteFragmentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/02/2023.
//

import SwiftUI

struct QuotedNoteFragmentView: View {
    @ObservedObject private var nrPost: NRPost
    @ObservedObject private var pfpAttributes: PFPAttributes
    @ObservedObject private var postRowDeletableAttributes: PostRowDeletableAttributes
    private var forceAutoload: Bool
    private var fullWidth: Bool
    private var theme: Theme
    @EnvironmentObject private var parentDIM: DIMENSIONS
    @State private var couldBeImposter: Int16
    
    init(nrPost: NRPost, fullWidth: Bool = false, forceAutoload: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.postRowDeletableAttributes = nrPost.postRowDeletableAttributes
        self.forceAutoload = forceAutoload
        self.fullWidth = fullWidth
        self.theme = theme
        self.couldBeImposter = nrPost.pfpAttributes.contact?.couldBeImposter ?? -1
    }
    
    var body: some View {
        if postRowDeletableAttributes.blocked {
            HStack {
                Text("_Post from blocked account hidden_", comment: "Message shown when a post is from a blocked account")
                Button(String(localized: "Reveal", comment: "Button to reveal a blocked a post")) { nrPost.blocked = false }
                    .buttonStyle(.bordered)
            }
            .padding(.leading, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.lineColor.opacity(0.5), lineWidth: 1)
            )
            .hCentered()
        }
        else {
            Text("hoho")
        }
    }
}

struct QuotedNoteFragmentView_Previews: PreviewProvider {
    
    static var previews: some View {
        
        // #[2]
        // 115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc
        
        // #[0]
        // 1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0
        
        // with youtube preview
        // id: 576375cd4a87e40f15a7842b43fe4a35651e89a34371b2a41ca79ca7dced1113
        
        // reply to unfetched contact
        // dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3
        
        // reply to known  contact
        // f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e
        
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            PreviewFeed {
                // Mention at #[5]
                if let event0 = PreviewFetcher.fetchNRPost("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe") {
                    Box {
                        PostRowDeletable(nrPost: event0)
                    }
                }
                
                
                if let event1 = PreviewFetcher.fetchNRPost("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3") {
                    Box {
                        QuotedNoteFragmentView(nrPost: event1, theme: Themes.default.theme)
                    }
                }
                
                if let event2 = PreviewFetcher.fetchNRPost("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e") {
                    Box {
                        QuotedNoteFragmentView(nrPost: event2, theme: Themes.default.theme)
                    }
                }
            }
        }
    }
}
