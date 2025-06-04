//
//  MinimalQuotedNoteFragment.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/02/2023.
//

import SwiftUI

struct MinimalQuotedNoteFragment: View {
    @ObservedObject var nrPost: NRPost
    public let fullWidth: Bool = false
    
    var body: some View {
        VStack(alignment:.leading) {
            HStack { // name + reply + context menu
                VStack(alignment: .leading) { // Name + menu "replying to"
                    HStack(spacing:2) {
                        // profile image
                        PFP(pubkey: nrPost.pubkey, nrContact: nrPost.contact, size: 20)
                        .opacity(0.5)
                        Text(nrPost.anyName) // Name
                            .font(.body)
                            .foregroundColor(.primary.opacity(0.5))
                            .fontWeight(.bold)
                            .lineLimit(1)
                        Text(" · \(nrPost.ago)") //
                            .font(.body)
                            .foregroundColor(.secondary)
                        if let via = nrPost.via {
                            Text(" · via \(via)") //
                                .lineLimit(1)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
            }
            VStack(alignment: .leading) {
                MinimalNoteTextRenderView(nrPost: nrPost)
            }
        }
        .padding(10)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(.regularMaterial, lineWidth: 1)
        )
        .onAppear {
            if (nrPost.contact == nil || nrPost.contact?.metadata_created_at == 0) {
                QueuedFetcher.shared.enqueue(pTag: nrPost.pubkey)
            }
        }
        .onDisappear {
            if (nrPost.contact == nil || nrPost.contact?.metadata_created_at == 0) {
                QueuedFetcher.shared.dequeue(pTag: nrPost.pubkey)
            }
        }
    }
}

struct MinimalQuotedNote_Previews: PreviewProvider {
    
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
            VStack {
                // Mention at #[5]
                let event0 = PreviewFetcher.fetchNRPost("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe")
            
                
                let event1 = PreviewFetcher.fetchNRPost("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3")
                
                let event2 = PreviewFetcher.fetchNRPost("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e")
                
                Spacer()
                if (event0 != nil) {
                    NoteMinimalContentView(nrPost: event0!)
                }
                
                if (event1 != nil) {
                    MinimalQuotedNoteFragment(nrPost: event1!)
                }
                if (event2 != nil) {
                    MinimalQuotedNoteFragment(nrPost: event2!)
                }
                Spacer()
            }
        }
    }
}
