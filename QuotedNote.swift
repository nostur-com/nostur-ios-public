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
import Nuke
import NukeUI
import CoreData

struct QuotedNoteFragment: View {
    
    @Environment(\.managedObjectContext) var viewContext
    var cm:SocketPool = .shared
    @EnvironmentObject var accountState:NosturState
    @ObservedObject var event:Event

    @FetchRequest
    var taggedContacts:FetchedResults<Contact>
    
    init(event: Event) {
        self.event = event
        let pubkeys = event.contactPubkeys()
        
        if (1 == 2) || (pubkeys == nil) {
            _taggedContacts = FetchRequest(
                sortDescriptors: [],
                predicate: NSPredicate(format: "FALSEPREDICATE")
            )
        }
        else { // TODO: IS THIS SLOW OR NOT?
            _taggedContacts = FetchRequest(
                sortDescriptors: [],
                predicate: NSPredicate(format: "pubkey IN %@", pubkeys!)
            )
        }
    }
    
    var body: some View {
        NavigationLink(value: event, label: {
            VStack(alignment:.leading) {
                HStack { // name + reply + context menu
                    VStack(alignment: .leading) { // Name + menu "replying to"
                        HStack(spacing:2) {
                            // profile image
                            if (event.contact != nil) {
                                NavigationLink(value: ContactPath(key: event.pubkey!), label: {
                                    ProfilePicView(pubkey: event.pubkey!, contact:event.contact, size: 20)
                                })
                            }
                            else {
                                NavigationLink(value: ContactPath(key: event.pubkey!), label: {
                                    ProfilePicView(pubkey: event.pubkey!, contact:event.contact, size: 20)
                                })
                            }
                            
                            Text(event.contact?.authorName ?? "Anon") // Name
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .fontWeight(.bold)
                                .lineLimit(1)
                            Text("@\(event.contact?.username ?? event.authorKey) · ") //
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            Text("\(event.ago)") //
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        
                        ReplyingToFragment(event: event)
                    }
                    
                    Spacer()
                }.frame(height: 40)
                VStack(alignment: .leading) {
                    NoteTextRenderView(event:event, taggedContacts:Array(taggedContacts))
                }
            }
        })
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
            if (event.contact == nil) {
                print("🟢 NoteRow.onAppear event.contact == nil so: REQ.0:\(event.pubkey!)")
                cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: event.pubkey!)))
            }
        }
    }
}

struct QuotedNote_Previews: PreviewProvider {
    
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
        let event0 = PreviewFetcher.fetchEvent("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe")
    
        
        let event1 = PreviewFetcher.fetchEvent("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3")
        
        let event2 = PreviewFetcher.fetchEvent("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e")
        
        VStack {
            
            Spacer()
            NoteRowView(event: event0!)
                .withPreviewEnvironment()
            QuotedNoteFragment(event: event1!)
                .withPreviewEnvironment()
            QuotedNoteFragment(event: event2!)
                .withPreviewEnvironment()
            Spacer()
        }
    }
}
