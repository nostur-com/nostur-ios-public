//
//  QuotedNote.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/02/2023.
//

//
//  MessageView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI

struct QuotedNoteFragmentView: View {
    @EnvironmentObject var accountState:NosturState
    @State var viewSize:CGSize = .zero
     
    @ObservedObject var nrPost:NRPost
    
    var body: some View {
        VStack(alignment:.leading) {
            HStack { // name + reply + context menu
                VStack(alignment: .leading) { // Name + menu "replying to"
                    HStack(spacing:2) {
                        // profile image
                        PFP(pubkey: nrPost.pubkey, nrContact: nrPost.contact, size: 20)
                            .onTapGesture {
                                navigateTo(ContactPath(key: nrPost.pubkey))
                            }
                            
                        if let contact = nrPost.contact {
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
                                .foregroundColor(.secondary)
                                .redacted(reason: .placeholder)
                        }
                        
                        Group {
                            Text(" ·") //
                            Ago(nrPost.createdAt)
                        }
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    ReplyingToFragmentView(nrPost: nrPost)
                }
                
                Spacer()
            }.frame(height: 40)
            VStack(alignment: .leading) {
//                RowContentRenderer(nrPost: nrPost)
//                DetailContentRenderer(event: nrPost.event)
                NoteTextRenderView(nrPost: nrPost)
                if nrPost.imageUrls.first != nil {
                    Color.clear.frame(height: 0)
                       .modifier(SizeModifier())
                       .onPreferenceChange(SizePreferenceKey.self) { size in
                           guard size.width > 0 else { return }
                           viewSize = size
                       }
                }
                if let firstMediaUrl = nrPost.imageUrls.first, firstMediaUrl.absoluteString.matchingStrings(regex: NRContentElementBuilder.videoUrlPattern).count > 0, viewSize.width > 0 {
                    SingleVideoViewer(url: firstMediaUrl, pubkey: nrPost.pubkey, videoWidth: viewSize.width - 20, isFollowing:nrPost.following)
                }
                else if let firstMediaUrl = nrPost.imageUrls.first, viewSize.width > 0 {
                    SingleMediaViewer(url: firstMediaUrl, pubkey: nrPost.pubkey, imageWidth: viewSize.width, isFollowing: nrPost.following)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            navigateTo(nrPost)
        }
        .padding(10)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(.regularMaterial, lineWidth: 1)
        )
        .onAppear {
            if (nrPost.contact == nil) || (nrPost.contact?.metadata_created_at == 0) {
                L.og.info("🟢 NoteRow.onAppear event.contact == nil so: REQ.0:\(nrPost.pubkey)")
                EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "NoteRow.onAppear")
                QueuedFetcher.shared.enqueue(pTag: nrPost.pubkey)
            }
        }
        .onDisappear {
            if (nrPost.contact == nil) || (nrPost.contact?.metadata_created_at == 0) {
                QueuedFetcher.shared.dequeue(pTag: nrPost.pubkey)
            }
        }
    }
    
    struct NameAndNip: View {
        @ObservedObject var contact:NRContact
        var body: some View {
            Text(contact.anyName) // Name
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .fontWeight(.bold)
                .lineLimit(1)
            if (contact.nip05verified) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(Color("AccentColor"))
                    .layoutPriority(3)
            }
//            Text("@\(contact.anyUsername)") //
//                .font(.system(size: 14))
//                .foregroundColor(.secondary)
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
    
        
        VStack {
            // Mention at #[5]
            if let event0 = PreviewFetcher.fetchNRPost("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe") {
                PostRowDeletable(nrPost: event0)
            }
        
            
            if let event1 = PreviewFetcher.fetchNRPost("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3") {
                QuotedNoteFragmentView(nrPost: event1)
            }
            
            if let event2 = PreviewFetcher.fetchNRPost("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e") {
                QuotedNoteFragmentView(nrPost: event2)
            }
        }
        .withPreviewEnvironment({ pe in
            pe.loadContacts()
            pe.loadPosts()
        })
    }
}
