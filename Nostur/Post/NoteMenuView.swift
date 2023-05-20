//
//  NoteMenuView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2023.
//

import SwiftUI

struct NoteMenuView: View {
    let up:Unpublisher = .shared
    @EnvironmentObject var ns:NosturState
    @ObservedObject var nrPost:NRPost
    
    var body: some View {
        ZStack {
            Color.systemBackground.frame(width: 45, height: 30)
                .offset(x: -5, y: 5)
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded {
                    // This prevents tap near but not on menu from navigating to post detail
                })
            Menu {
                Group {
                    Button {
                        guard let contact = nrPost.mainEvent.contact else { return }
                        sendNotification(.addRemoveToListsheet, contact)
                    } label: {
                        Label("Add/Remove from lists", systemImage: "person.2.crop.square.stack")
                    }
                    Button {
                        if let pn = nrPost.mainEvent.privateNote {
                            sendNotification(.editingPrivateNote, pn)
                        }
                        else {
                            sendNotification(.newPrivateNoteOnPost, nrPost.id)
                        }
                    } label: {
                        Label("Add private note", systemImage: "note.text")
                    }
                    Button {
                        UIPasteboard.general.string = nrPost.mainEvent.noteId
                    } label: {
                        Label("Copy post id", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        UIPasteboard.general.string = nrPost.id
                    } label: {
                        Label("Copy post id (hex)", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        UIPasteboard.general.string = nrPost.mainEvent.plainText
                    } label: {
                        Label("Copy text", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        UIPasteboard.general.string = nrPost.mainEvent.toNEvent().eventJson()
                    } label: {
                        Label("Copy source", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        if (nrPost.mainEvent.contact != nil) {
                            ns.follow(nrPost.mainEvent.contact!)
                        }
                    } label: {
                        Label("Follow \(nrPost.anyName)", systemImage: "person.fill")
                    }
                }

                Button {
                    if (nrPost.mainEvent.contact == nil) {
                        // TODO: Contact is created so it can be unblocked in Blocklist. Should not have to create contact just for this.
                        _ = DataProvider.shared().newContact(pubkey: nrPost.event.pubkey)
                        ns.objectWillChange.send()
                        ns.account!.blockedPubkeys_ = ns.account!.blockedPubkeys_ + [nrPost.pubkey]
                    }
                    else {
                        ns.objectWillChange.send()
                        ns.account!.blockedPubkeys_ = ns.account!.blockedPubkeys_ + [nrPost.pubkey]
                    }
                    sendNotification(.blockListUpdated, ns.account!.blockedPubkeys_)
                } label: {
                    Label("Block \(nrPost.anyName)", systemImage: "slash.circle")
                }
                
                Button {
                    print("Mute conversation")
                    ns.muteConversation(nrPost)
                } label: {
                    Label("Mute conversation", systemImage: "bell.slash.fill")
                }
                
                Button { sendNotification(.reportPost, nrPost) } label: {
                    Label("Report", systemImage: "flag")
                }
                
                if (NosturState.shared.activeAccountPublicKey == nrPost.pubkey) {
                    Button { sendNotification(.requestDeletePost, nrPost.id) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                
                Button {
                    guard ns.account != nil else { return }
                    let nEvent = nrPost.mainEvent.toNEvent()
                    up.publishNow(nEvent)
                } label: {
                    Label("Rebroadcast\(nrPost.pubkey == NosturState.shared.activeAccountPublicKey ? " (again)" : "")", systemImage: "dot.radiowaves.left.and.right")
                }
                
                if nrPost.relays != "" {
                    Group {
                        Divider()
                        ForEach(nrPost.relays.split(separator: " "), id:\.self) { relay in
                            Button(String(relay)) { }
                                .disabled(true)
                        }
                    }
                }
                
            } label: {
                Image(systemName: "ellipsis")
                    .fontWeight(.bold)
                    .foregroundColor(Color.init(red: 113/255, green: 118/255, blue: 123/255))
                    .padding(.top, 7)
                    .padding(.bottom, 6)
                    .padding(.leading, 10)
            }
        }
    }
    
}

struct NoteMenuView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            if let event7 = PreviewFetcher.fetchNRPost() {
                NoteMenuView(nrPost: event7)
            }
            Spacer()
        }
        .withPreviewEnvironment()
    }
}
