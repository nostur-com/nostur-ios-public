//
//  NoteMenu.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/02/2023.
//

import SwiftUI

struct NoteMenu: View {
    @EnvironmentObject var up:Unpublisher
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    var event:Event
    
    var noteIdHex:String { event.id }
    var noteId:String { get { event.noteId } }
    var username:String {
        get {
            event.contact?.username ?? String((event.pubkey).prefix(5))
        }
    }
    
    var body: some View {
        Menu {
            Button {
                UIPasteboard.general.string = noteId
            } label: {
                Label("Copy note id \(noteId)", systemImage: "doc.on.clipboard")
            }
            Button {
                UIPasteboard.general.string = noteIdHex
            } label: {
                Label("Copy note id hex \(noteIdHex))", systemImage: "doc.on.clipboard")
            }
            if (ns.isFollowing(event.pubkey)) {
                Button {
                    print("Unfollow @\(username)")
                    if (event.contact != nil) {
                        ns.unfollow(event.contact!)
                    }
                } label: {
                    Label("Unfollow @\(username)", systemImage: "person.fill.xmark")
                }
            }
            else {
                Button {
                    print("Follow @\(username)")
                    if (event.contact != nil) {
                        ns.follow(event.contact!)
                    }
                } label: {
                    Label("Follow @\(username)", systemImage: "person.fill")
                }
            }
            Button {
                print("Block @\(username)")
                if (event.contact == nil) {
                    // TODO: Contact is created so it can be unblocked in Blocklist. Should not have to create contact just for this.
                    let newContact = Contact(context: viewContext)
                    newContact.pubkey = event.pubkey
                    newContact.updated_at = 0
                    ns.objectWillChange.send()
                    ns.account!.blockedPubkeys_ = ns.account!.blockedPubkeys_ + [event.pubkey]
                }
                else {
                    ns.objectWillChange.send()
                    ns.account!.blockedPubkeys_ = ns.account!.blockedPubkeys_ + [event.pubkey]
                }
                do {
                    try viewContext.save()
                    sendNotification(.blockListUpdated, ns.account!.blockedPubkeys_)
                }
                catch {
                    print("Could not save after blocking contact \(error)")
                }
                
                
            } label: {
                Label("Block @\(username)", systemImage: "slash.circle")
            }
            
            Button {
                guard ns.account != nil else { return }
                print("Mute conversation")
                if let replyToRootId = event.replyToRootId {
                    ns.account?.mutedRootIds_ = ns.account!.mutedRootIds_ + [replyToRootId, event.id]
                    print("Muting \(replyToRootId)")
                }
                else if let firstE = event.firstE() {
                    ns.account?.mutedRootIds_ = ns.account!.mutedRootIds_ + [firstE, event.id]
                    print("Muting \(firstE)")
                }
                do {
                    try viewContext.save()
                }
                catch {
                    print("Could not save after muting thread \(error)")
                }
            } label: {
                Label("Mute conversation", systemImage: "bell.slash.fill")
            }
            
            Button {
                guard ns.account != nil else { return }
                let nEvent = event.toNEvent()
                up.publishNow(nEvent)
            } label: {
                Label("Rebroadcast (again)", systemImage: "radiowaves.left.and.right")
            }
        } label: {
            Text("···")
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .padding(.top, 0)
                .padding(.bottom, 10)
                .padding(.leading, 20)
                .padding(.trailing, 10)
            
        }
    }
}
struct NoteMenu_Previews: PreviewProvider {
    static var previews: some View {
        let event7 = PreviewFetcher.fetchEvent("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
        if (event7 != nil) {
            NoteMenu(event: event7!)
                .withPreviewEnvironment()
        }
    }
}
