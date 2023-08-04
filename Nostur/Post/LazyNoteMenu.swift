//
//  LazyNoteMenu.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/05/2023.
//

import SwiftUI

struct LazyNoteMenuButton: View {
    var nrPost:NRPost
    static let color = Color(red: 113/255, green: 118/255, blue: 123/255)
    
    var body: some View {
        Image(systemName: "ellipsis")
            .fontWeight(.bold)
            .foregroundColor(Self.color)
            .padding(.top, 7)
            .padding(.bottom, 6)
            .padding(.leading, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                sendNotification(.showNoteMenu, nrPost)
            }
    }
}

struct LazyNoteMenuSheet: View {
    let nrPost:NRPost
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
                        DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                            sendNotification(.sharePostScreenshot, nrPost)
                        }
                    } label: {
                        Label(String(localized:"Share post", comment: "Post context menu button"), systemImage: "square.and.arrow.up")
                    }
                    Button {
                        dismiss()
                        guard let contact = nrPost.mainEvent.contact else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                            sendNotification(.addRemoveToListsheet, contact)
                        }
                    } label: {
                        Label(String(localized:"Add/Remove \(nrPost.anyName) from lists", comment: "Post context menu button"), systemImage: "person.2.crop.square.stack")
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
                        Label(String(localized:"Add private note", comment: "Post context menu button"), systemImage: "note.text")
                    }
                    HStack {
                        Button {
                            UIPasteboard.general.string = nrPost.mainEvent.plainText
                            dismiss()
                        } label: {
                            Label(String(localized:"Copy post text", comment: "Post context menu button"), systemImage: "doc.on.clipboard")
                                .padding(.trailing, 5)
                        }
                        .buttonStyle(.plain)
                        Divider()
                        Button {
                            UIPasteboard.general.string = nrPost.mainEvent.noteId
                            dismiss()
                        } label: {
                            Text("ID", comment:"Label for post identifier (ID)")
                                .padding(.horizontal, 5)
                        }
                        .buttonStyle(.plain)
                        .overlay(
                            Color.white
                                .opacity(0.01)
                                .scaleEffect(x: 1.75, y:1.7)
                        )
                        .onTapGesture {
                            UIPasteboard.general.string = nrPost.mainEvent.noteId
                            dismiss()
                        }
                        
                        Divider()
                        Button {
                            UIPasteboard.general.string = nrPost.id
                            dismiss()
                        } label: {
                            Text("hex", comment: "Short label for the word 'hexadecimal'")
                                .padding(.horizontal, 5)
                        }
                        .buttonStyle(.plain)
                        .overlay(
                            Color.white
                                .opacity(0.01)
                                .scaleEffect(x: 1.3, y:1.7)
                        )
                        .onTapGesture {
                            UIPasteboard.general.string = nrPost.id
                            dismiss()
                        }
                        Divider()
                        Button {
                            dismiss()
                            UIPasteboard.general.string = nrPost.mainEvent.toNEvent().eventJson()
                        } label: {
                            Text("source", comment: "The word 'source' as in source code")
                                .padding(.horizontal, 5)
                        }
                        .buttonStyle(.plain)
                        .overlay(
                            Color.white
                                .opacity(0.01)
                                .scaleEffect(x: 1.35, y:1.7)
                        )
                        .onTapGesture {
                            dismiss()
                            UIPasteboard.general.string = nrPost.mainEvent.toNEvent().eventJson()
                        }
                    }
                    Button {
                        dismiss()
                        if (nrPost.mainEvent.contact != nil) {
                            ns.follow(nrPost.mainEvent.contact!)
                        }
                    } label: {
                        Label(String(localized:"Follow \(nrPost.anyName)", comment: "Post context menu button to Follow (name)"), systemImage: "person.fill")
                    }
                }
                
                Button {
                    dismiss()
                    if (nrPost.mainEvent.contact == nil) {
                        // TODO: Contact is created so it can be unblocked in Blocklist. Should not have to create contact just for this.
                        _ = DataProvider.shared().newContact(pubkey: nrPost.event.pubkey)
                        DataProvider.shared().bg.perform {
                            guard let account = ns.account?.toBG() else { return }
                            let newBlockedKeys = account.blockedPubkeys_ + [nrPost.pubkey]
                            account.blockedPubkeys_ = newBlockedKeys
                            
                            DataProvider.shared().bgSave()
                            DispatchQueue.main.async {
                                sendNotification(.blockListUpdated, newBlockedKeys)
                            }
                        }
                    }
                    else {
                        DataProvider.shared().bg.perform {
                            guard let account = ns.account?.toBG() else { return }
                            let newBlockedKeys = account.blockedPubkeys_ + [nrPost.pubkey]
                            account.blockedPubkeys_ = newBlockedKeys
                            
                            DataProvider.shared().bgSave()
                            DispatchQueue.main.async {
                                sendNotification(.blockListUpdated, newBlockedKeys)
                            }
                        }
                    }
                } label: {
                    Label(String(localized:"Block \(nrPost.anyName)", comment: "Post context menu action to Block (name)"), systemImage: "slash.circle")
                }
                
                Button {
                    dismiss()
                    L.og.info("Mute conversation")
                    ns.muteConversation(nrPost)
                } label: {
                    Label(String(localized:"Mute conversation", comment: "Post context menu action to mute conversation"), systemImage: "bell.slash.fill")
                }
                
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                        sendNotification(.reportPost, nrPost)
                    }
                } label: {
                    Label(String(localized:"Report.verb", comment:"Post context menu action to Report a post or user"), systemImage: "flag")
                }
                
                if (NosturState.shared.activeAccountPublicKey == nrPost.pubkey) {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                            sendNotification(.requestDeletePost, nrPost.id)
                        }
                    } label: {
                        Label(String(localized:"Delete", comment:"Post context menu action to Delete a post"), systemImage: "trash")
                    }
                }
                
                Button {
                    dismiss()
                    guard let account = ns.account else { return }
                    let nEvent = nrPost.mainEvent.toNEvent()                    
                    
                    if nrPost.pubkey == NosturState.shared.activeAccountPublicKey && nrPost.mainEvent.flags == "nsecbunker_unsigned" && account.isNC {
                        NosturState.shared.nsecBunker?.requestSignature(forEvent: nEvent, whenSigned: { signedEvent in
                            Unpublisher.shared.publishNow(signedEvent)
                        })
                    }
                    else {
                        up.publishNow(nEvent)
                    }
                } label: {
                    if nrPost.pubkey == NosturState.shared.activeAccountPublicKey {
                        Label(String(localized:"Rebroadcast (again)", comment: "Button to broadcast own post again"), systemImage: "dot.radiowaves.left.and.right")
                    }
                    else {
                        Label(String(localized:"Rebroadcast", comment: "Button to rebroadcast a post"), systemImage: "dot.radiowaves.left.and.right")
                    }
                }
                
                if nrPost.relays != "" {
                    VStack(alignment: .leading) {
                        if let pubkey = ns.account?.publicKey, pubkey == nrPost.pubkey {
                            Text("Sent to:", comment:"Heading for list of relays sent to")
                        }
                        else {
                            Text("Received from:", comment:"Heading for list of relays received from")
                        }
                        ForEach(nrPost.relays.split(separator: " "), id:\.self) { relay in
                            Text(String(relay)).lineLimit(1)
                        }
                    }.foregroundColor(.gray)
                }
            }
            .listStyle(.plain)
            .navigationTitle(String(localized:"Post actions", comment:"Title of sheet showing actions to perform on post"))
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

struct LazyNoteMenuSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadPosts() }) {
            VStack {
                if let nrPost = PreviewFetcher.fetchNRPost() {
                    LazyNoteMenuSheet(nrPost:nrPost)
                }
            }
        }
    }
}

struct LazyNoteMenu_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadPosts()
        }) {
            VStack {
                if let nrPost = PreviewFetcher.fetchNRPost() {
                    LazyNoteMenuButton(nrPost:nrPost)
                }
                Color.clear.withSheets()
            }
        }
    }
}
