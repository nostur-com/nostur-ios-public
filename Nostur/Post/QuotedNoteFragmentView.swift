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
     
    let nrPost:NRPost
//    @ObservedObject var event:Event
    
    init(nrPost: NRPost) {
        self.nrPost = nrPost
//        self.event = nrPost.event
    }
    
    var body: some View {
        VStack(alignment:.leading) {
            HStack { // name + reply + context menu
                VStack(alignment: .leading) { // Name + menu "replying to"
                    HStack(spacing:2) {
                        // profile image
                        PFP(pubkey: nrPost.pubkey, pictureUrl: nrPost.contact?.pictureUrl, size: 20, isFollowing: nrPost.contact?.following ?? false)
                            .onTapGesture {
                                navigateTo(ContactPath(key: nrPost.pubkey)) // TODO: Direct to nrPost.vContact if possible
                            }
                            
                        if let contact = nrPost.contact {
//                            NameAndNip(contact: contact)
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
                if let firstImage = nrPost.imageUrls.first, viewSize.width > 0 {
                    SingleMediaViewer(url: firstImage, pubkey: nrPost.pubkey, imageWidth: viewSize.width, isFollowing: nrPost.contact?.following ?? false)
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
            // should fetch setMetaData if
            // No Contact
            // Contact updated_at is very old
            // followed contact meta data refresh should be updated at app wake up probably
            if (nrPost.contact == nil) || (nrPost.contact?.metadata_created_at == 0) {
                print("🟢 NoteRow.onAppear event.contact == nil so: REQ.0:\(nrPost.pubkey)")
                // TODO: FIXXXX
//                EventRelationsQueue.shared.addAwaitingEvent(nrPost.event)
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
            Text(contact.displayName ?? "") // Name
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .fontWeight(.bold)
                .lineLimit(1)
            if (contact.nip05verified) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(Color("AccentColor"))
                    .layoutPriority(3)
            }
            Text("@\(contact.anyUsername)") //
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
    }
}

struct QuotedNoteFragmentView_Previews: PreviewProvider {
    
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
    
        
        VStack {
            // Mention at #[5]
            let event0 = PreviewFetcher.fetchNRPost("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe")
        
            
            let event1 = PreviewFetcher.fetchNRPost("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3")
            
            let event2 = PreviewFetcher.fetchNRPost("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e")
            
            Spacer()
            if (event0 != nil) {
                PostRowDeletable(nrPost: event0!)
            }
            
            if (event1 != nil) {
                QuotedNoteFragmentView(nrPost: event1!)
            }
            if (event2 != nil) {
                QuotedNoteFragmentView(nrPost: event2!)
            }
            Spacer()
        }
        .withPreviewEnvironment()
    }
}
