//
//  MinimalQuotedNoteFragment.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/02/2023.
//

import SwiftUI
import Compactor

struct MinimalQuotedNoteFragment: View {
    var sp:SocketPool = .shared
    var vPost:VPost
    
    var body: some View {
        VStack(alignment:.leading) {
            HStack { // name + reply + context menu
                VStack(alignment: .leading) { // Name + menu "replying to"
                    HStack(spacing:2) {
                        // profile image
                        PFP(pubkey: vPost.event.pubkey, pictureUrl: vPost.event.contact?.picture, size: 20)
                        .opacity(0.5)
                        if let contact = vPost.event.contact {
                            NameAndNip(contact: contact)
                        }
                        else {
                            Text("Anon")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .fontWeight(.bold)
                                .lineLimit(1).redacted(reason: .placeholder)
                            Text("@Anon") //
                                .font(.system(size: 14))
                                .foregroundColor(.secondary.opacity(0.5))
                                .redacted(reason: .placeholder)
                        }
                        Text(" · \(vPost.event.ago)") //
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            VStack(alignment: .leading) {
                MinimalNoteTextRenderView(vPost: vPost)
            }
        }
        .padding(10)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(.regularMaterial, lineWidth: 1)
        )
        .onAppear {
            if (vPost.event.contact == nil) {
                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: vPost.event.pubkey)))
            }
        }
    }
    
    struct NameAndNip: View {
        @ObservedObject var contact:Contact // for rendering nip check (after just verified) etc
 
        var body: some View {
            Text(contact.authorName) // Name
                .font(.system(size: 14))
                .foregroundColor(.primary.opacity(0.5))
                .fontWeight(.bold)
                .lineLimit(1)
            
            if (contact.nip05veried) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(Color("AccentColor"))
                    .layoutPriority(3)
            }
            
            Text("@\(contact.username)") //
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.5))
        }
    }
}

struct MinimalQuotedNote_Previews: PreviewProvider {
    
    static var previews: some View {
        
        // #[2]
        // 115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc
        
        // #[0]
        // 1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0
        
        // note.id 6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81
        // pubkey: 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0
        
        // with youtube preview
        // id: 576375cd4a87e40f15a7842b43fe4a35651e89a34371b2a41ca79ca7dced1113
        
        // reply to unfetched contact
        // dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3
        
        // reply to known  contact
        // f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e
    
        // Mention at #[5]
        let event0 = PreviewFetcher.fetchVPost("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe")
    
        
        let event1 = PreviewFetcher.fetchVPost("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3")
        
        let event2 = PreviewFetcher.fetchVPost("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e")
        
        VStack {
            Spacer()
            if (event0 != nil) {
                NoteMinimalContentView(vPost: event0!)
            }
            
            if (event1 != nil) {
                MinimalQuotedNoteFragment(vPost: event1!)
            }
            if (event2 != nil) {
                MinimalQuotedNoteFragment(vPost: event2!)
            }
            Spacer()
        }
        .withPreviewEnvironment()
    }
}
