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
    
    var body: some View {
        Menu {
            Button {
                if vPost.hasPrivateNote {
                    sendNotification(.editingPrivateNoteOnPost, vPost.id)
                }
                else {
                    sendNotification(.newPrivateNoteOnPost, vPost.id)
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
                UIPasteboard.general.string = vPost.id
            } label: {
                Label("Copy note id (hex) \(String(vPost.id.prefix(11)))...", systemImage: "doc.on.clipboard")
            }
            Button {
                UIPasteboard.general.string = vPost.plainText
            } label: {
                Label("Copy text", systemImage: "doc.on.clipboard")
            }
            Button {
                UIPasteboard.general.string = vPost.post.toNEvent().eventJson()
            } label: {
                Label("Copy source", systemImage: "doc.on.clipboard")
            }
            if (vPost.vContact?.isFollowing ?? false) {
                Button {
                    print("Unfollow @\(vPost.username)")
                    if (vPost.post.contact != nil) {
                        ns.unfollow(vPost.post.contact!)
                    }
                } label: {
                    Label("Unfollow @\(vPost.username)", systemImage: "person.fill.xmark")
                }
            }
            else {
                Button {
                    print("Follow @\(vPost.username)")
                    if (vPost.vContact != nil) {
                        ns.follow(vPost.post.contact!)
                    }
                } label: {
                    Label("Follow @\(vPost.username)", systemImage: "person.fill")
                }
            }
            Button {
                // TODO: MOVE TO NostureState, like follow/muteConversation etc.
                print("Block @\(vPost.username)")
                if (vPost.post.contact == nil) {
                    // TODO: Contact is created so it can be unblocked in Blocklist. Should not have to create contact just for this.
                    _ = DataProvider.shared().newContact(pubkey: vPost.pubkey)
                    ns.objectWillChange.send()
                    ns.account!.blockedPubkeys_ = ns.account!.blockedPubkeys_ + [vPost.pubkey]
                }
                else {
                    ns.objectWillChange.send()
                    ns.account!.blockedPubkeys_ = ns.account!.blockedPubkeys_ + [vPost.pubkey]
                }
                sendNotification(.blockListUpdated, ns.account!.blockedPubkeys_)
            } label: {
                Label("Block @\(vPost.username)", systemImage: "slash.circle")
            }
            
            Button {
                print("Mute conversation")
                ns.muteConversation(vPost)
            } label: {
                Label("Mute conversation", systemImage: "bell.slash.fill")
            }
            
            Button {
                guard ns.account != nil else { return }
                let nEvent = vPost.post.toNEvent()
                up.publishNow(nEvent)
            } label: {
                Label("Rebroadcast\(vPost.pubkey == ns.activeAccountPublicKey ? " (again)" : "")", systemImage: "radiowaves.left.and.right")
            }
        } label: {
            Text("···")
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .padding(.top, 0)
                .padding(.bottom, 5)
                .padding(.leading, 20)
                .padding(.trailing, 10)
            
        }
    }
    
}

struct NoteMenuView_Previews: PreviewProvider {
    static var previews: some View {
        let event7 = PreviewFetcher.fetchVPost()
        if (event7 != nil) {
            NoteMenuView(vPost: event7!)
                .withPreviewEnvironment()
        }
    }
}
