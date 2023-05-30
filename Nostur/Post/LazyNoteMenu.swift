//
//  LazyNoteMenu.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/05/2023.
//

import SwiftUI

struct LazyNoteMenuButton: View {
    var nrPost:NRPost
    var body: some View {
        Button {
            sendNotification(.showNoteMenu, nrPost)
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

struct LazyNoteMenuSheet: View {
    @ObservedObject var nrPost:NRPost
    @EnvironmentObject var ns:NosturState
    @Environment(\.dismiss) var dismiss
    let up:Unpublisher = .shared
    let NEXT_SHEET_DELAY = 0.05
    
    var body: some View {
        NavigationStack {
            List {
                Group {
                    Button {
                        dismiss()
                        guard let contact = nrPost.mainEvent.contact else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                            sendNotification(.addRemoveToListsheet, contact)
                        }
                    } label: {
                        Label("Add/Remove \(nrPost.anyName) from lists", systemImage: "person.2.crop.square.stack")
                    }
                    Button {
                        dismiss()
                        if let pn = nrPost.mainEvent.privateNote {
                            DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                                sendNotification(.editingPrivateNote, pn)
                            }
                        }
                        else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                                sendNotification(.newPrivateNoteOnPost, nrPost.id)
                            }
                        }
                    } label: {
                        Label("Add private note", systemImage: "note.text")
                    }
                    HStack {
                        Button {
                            UIPasteboard.general.string = nrPost.mainEvent.plainText
                            dismiss()
                        } label: {
                            Label("Copy post text", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.plain)
                        Divider()
                        Button {
                            UIPasteboard.general.string = nrPost.mainEvent.noteId
                            dismiss()
                        } label: {
                            Text("ID")
                                .padding(.horizontal, 5)
                        }
                        .buttonStyle(.plain)
                        Divider()
                        Button {
                            UIPasteboard.general.string = nrPost.id
                            dismiss()
                        } label: {
                            Text("hex")
                                .padding(.horizontal, 5)
    //                        Label("Copy hex", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.plain)
                        Divider()
                        Button {
                            dismiss()
                            UIPasteboard.general.string = nrPost.mainEvent.toNEvent().eventJson()
                        } label: {
                            Text("source")
    //                        Label("Copy source", systemImage: "doc.on.clipboard")
                        }
                    }
                    Button {
                        dismiss()
                        if (nrPost.mainEvent.contact != nil) {
                            ns.follow(nrPost.mainEvent.contact!)
                        }
                    } label: {
                        Label("Follow \(nrPost.anyName)", systemImage: "person.fill")
                    }
                }

                Button {
                    dismiss()
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
                    dismiss()
                    print("Mute conversation")
                    ns.muteConversation(nrPost)
                } label: {
                    Label("Mute conversation", systemImage: "bell.slash.fill")
                }

                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                        sendNotification(.reportPost, nrPost)
                    }
                } label: {
                    Label("Report", systemImage: "flag")
                }

                if (NosturState.shared.activeAccountPublicKey == nrPost.pubkey) {
                    Button {
                        dismiss()
                        sendNotification(.requestDeletePost, nrPost.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

                Button {
                    dismiss()
                    guard ns.account != nil else { return }
                    let nEvent = nrPost.mainEvent.toNEvent()
                    up.publishNow(nEvent)
                } label: {
                    Label("Rebroadcast\(nrPost.pubkey == NosturState.shared.activeAccountPublicKey ? " (again)" : "")", systemImage: "dot.radiowaves.left.and.right")
                }

                if nrPost.relays != "" {
                    VStack(alignment: .leading) {
                        if let pubkey = ns.account?.publicKey, pubkey == nrPost.pubkey {
                            Text("Sent to:")
                        }
                        else {
                            Text("Received from:")
                        }
                        ForEach(nrPost.relays.split(separator: " "), id:\.self) { relay in
                            Text(String(relay)).lineLimit(1)
                        }
                    }.foregroundColor(.gray)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Post actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Text("Cancel")
                    }

                }
            }
        }
    }
}

struct LazyNoteMenu_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            if let nrPost = PreviewFetcher.fetchNRPost() {
                LazyNoteMenuButton(nrPost:nrPost)
            }
            Color.clear.withSheets()
        }
        .withPreviewEnvironment({ pe in
            pe.loadPosts()
        })
    }
}
