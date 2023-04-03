//
//  NoteMenuView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2023.
//

import SwiftUI

struct NoteMenuView: View {
    @EnvironmentObject var up:Unpublisher
    @EnvironmentObject var ns:NosturState
    var vPost:VPost
    @ObservedObject var event:Event
    
    init(vPost: VPost) {
        self.vPost = vPost
        self.event = vPost.event
    }
    
    var body: some View {
        Menu {
            Button {
                if let pn = event.privateNote {
                    sendNotification(.editingPrivateNote, pn)
                }
                else {
                    sendNotification(.newPrivateNoteOnPost, event.id)
                }
            } label: {
                Label("Add private note", systemImage: "note.text")
            }
            Button {
                UIPasteboard.general.string = vPost.note1
            } label: {
                Label("Copy note id \(String(vPost.note1.prefix(11)))...", systemImage: "doc.on.clipboard")
            }
            Button {
                UIPasteboard.general.string = vPost.event.id
            } label: {
                Label("Copy note id (hex) \(String(vPost.event.id.prefix(11)))...", systemImage: "doc.on.clipboard")
            }
            Button {
                UIPasteboard.general.string = vPost.plainText
            } label: {
                Label("Copy text", systemImage: "doc.on.clipboard")
            }
            Button {
                UIPasteboard.general.string = vPost.event.toNEvent().eventJson()
            } label: {
                Label("Copy source", systemImage: "doc.on.clipboard")
            }
//            if (vPost.vContact?.isFollowing ?? false) { // TODO:FIXME
            
//            Button {
//                print("Unfollow @\(vPost.event.username ?? vPost.event.username)")
//                if (vPost.event.contact != nil) {
//                    ns.unfollow(vPost.event.contact!)
//                }
//            } label: {
//                Label("Unfollow @\(vPost.event.username)", systemImage: "person.fill.xmark")
//            }
            
            Button {
                print("Follow @\(vPost.event.username)")
                if (vPost.event.contact != nil) {
                    ns.follow(vPost.event.contact!)
                }
            } label: {
                Label("Follow @\(vPost.event.username)", systemImage: "person.fill")
            }

            Button {
                // TODO: MOVE TO NostureState, like follow/muteConversation etc.
                print("Block @\(vPost.event.username)")
                if (vPost.event.contact == nil) {
                    // TODO: Contact is created so it can be unblocked in Blocklist. Should not have to create contact just for this.
                    _ = DataProvider.shared().newContact(pubkey: vPost.event.pubkey)
                    ns.objectWillChange.send()
                    ns.account!.blockedPubkeys_ = ns.account!.blockedPubkeys_ + [vPost.event.pubkey]
                }
                else {
                    ns.objectWillChange.send()
                    ns.account!.blockedPubkeys_ = ns.account!.blockedPubkeys_ + [vPost.event.pubkey]
                }
                sendNotification(.blockListUpdated, ns.account!.blockedPubkeys_)
            } label: {
                Label("Block @\(vPost.event.username)", systemImage: "slash.circle")
            }
            
            Button {
                print("Mute conversation")
                ns.muteConversation(vPost)
            } label: {
                Label("Mute conversation", systemImage: "bell.slash.fill")
            }
            
            Button {
                guard ns.account != nil else { return }
                let nEvent = vPost.event.toNEvent()
                up.publishNow(nEvent)
            } label: {
                Label("Rebroadcast\(vPost.event.pubkey == ns.activeAccountPublicKey ? " (again)" : "")", systemImage: "dot.radiowaves.left.and.right")
            }
            if event.relays != "" {
                Divider()
                ForEach(event.relays.split(separator: " "), id:\.self) { relay in
                    Button(String(relay)) { }
                        .disabled(true)
                }
            }
            
        } label: {
            Text("···")
                .fontWeight(.bold)
                .foregroundColor(Color.init(red: 113/255, green: 118/255, blue: 123/255))
                .padding(.top, 0)
                .padding(.bottom, 5)
                .padding(.leading, 20)
//                .padding(.trailing, 10)
            
        }
    }
    
}

struct NoteMenuSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var up:Unpublisher
    @EnvironmentObject var ns:NosturState
    var vPost:VPost
    @ObservedObject var event:Event
    
    init(vPost: VPost) {
        self.vPost = vPost
        self.event = vPost.event
    }
    
    var body: some View {
        VStack(alignment:.leading, spacing: 10) {
            Group {
                Button {
                    if let pn = event.privateNote {
                        sendNotification(.editingPrivateNote, pn)
                    }
                    else {
                        sendNotification(.newPrivateNoteOnPost, event.id)
                    }
                } label: {
                    Label("Add private note", systemImage: "note.text")
                }
                Button {
                    UIPasteboard.general.string = vPost.note1
                } label: {
                    Label("Copy note id \(String(vPost.note1.prefix(11)))...", systemImage: "doc.on.clipboard")
                }
                Button {
                    UIPasteboard.general.string = vPost.event.id
                } label: {
                    Label("Copy note id (hex) \(String(vPost.event.id.prefix(11)))...", systemImage: "doc.on.clipboard")
                }
                Button {
                    UIPasteboard.general.string = vPost.plainText
                } label: {
                    Label("Copy text", systemImage: "doc.on.clipboard")
                }
                Button {
                    UIPasteboard.general.string = vPost.event.toNEvent().eventJson()
                } label: {
                    Label("Copy source", systemImage: "doc.on.clipboard")
                }
                //            if (vPost.vContact?.isFollowing ?? false) { // TODO:FIXME
                
//                Button {
//                    print("Unfollow @\(vPost.event.username)")
//                    if (vPost.event.contact != nil) {
//                        ns.unfollow(vPost.event.contact!)
//                    }
//                } label: {
//                    Label("Unfollow @\(vPost.event.username)", systemImage: "person.fill.xmark")
//                }
                
                Button {
                    print("Follow @\(vPost.event.username)")
                    if (vPost.event.contact != nil) {
                        ns.follow(vPost.event.contact!)
                    }
                } label: {
                    Label("Follow @\(vPost.event.username)", systemImage: "person.fill")
                }
                
                Button {
                    // TODO: MOVE TO NostureState, like follow/muteConversation etc.
                    print("Block @\(vPost.event.username)")
                    if (vPost.event.contact == nil) {
                        // TODO: Contact is created so it can be unblocked in Blocklist. Should not have to create contact just for this.
                        _ = DataProvider.shared().newContact(pubkey: vPost.event.pubkey)
                        ns.objectWillChange.send()
                        ns.account!.blockedPubkeys_ = ns.account!.blockedPubkeys_ + [vPost.event.pubkey]
                    }
                    else {
                        ns.objectWillChange.send()
                        ns.account!.blockedPubkeys_ = ns.account!.blockedPubkeys_ + [vPost.event.pubkey]
                    }
                    sendNotification(.blockListUpdated, ns.account!.blockedPubkeys_)
                } label: {
                    Label("Block @\(vPost.event.username)", systemImage: "slash.circle")
                }
                
                Button {
                    print("Mute conversation")
                    ns.muteConversation(vPost)
                } label: {
                    Label("Mute conversation", systemImage: "bell.slash.fill")
                }
                
                Button {
                    guard ns.account != nil else { return }
                    let nEvent = vPost.event.toNEvent()
                    up.publishNow(nEvent)
                } label: {
                    Label("Rebroadcast\(vPost.event.pubkey == ns.activeAccountPublicKey ? " (again)" : "")", systemImage: "dot.radiowaves.left.and.right")
                }
                if event.relays != "" {
                    Divider()
                    ForEach(event.relays.split(separator: " "), id:\.self) { relay in
                        Button(String(relay)) { }
                            .disabled(true)
                    }
                }
            }
            
        }
//        .buttonStyle(.borderedProminent)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            }
        }
    }
    
}

struct NoteMenuView_Previews: PreviewProvider {
    static var previews: some View {
        let event7 = PreviewFetcher.fetchVPost()
        if (event7 != nil) {
            NoteMenuSheet(vPost: event7!)
                .withPreviewEnvironment()
        }
    }
}
