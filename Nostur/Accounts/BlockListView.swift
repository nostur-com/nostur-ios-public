//
//  BlockListView.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/02/2023.
//

import SwiftUI

struct BlockListView: View {
    @EnvironmentObject var themes: Themes
    @State var tab = "Blocked"
    
    var body: some View {
        VStack {
            HStack {
                TabButton(action: {
                    tab = "Blocked"
                }, title: String(localized: "Blocked", comment: "Title of tab where Blocked users are listed"), selected: tab == "Blocked")
                
                TabButton(action: {
                    tab = "Muted"
                }, title: String(localized:"Muted conversations", comment:"Title of tab where Muted conversations are listed"), selected: tab == "Muted")
                //                TabButton(action: {
                //                        tab = "Muted words"
                //                }, title: "Muted words", selected: tab == "Muted words")
            }
            switch tab {
            case "Blocked":
                BlockedAccounts()
                Text("Swipe to unblock/unmute", comment: "Informational text")
            case "Muted":
                MutedConversations()
                Text("Swipe to unblock/unmute", comment: "Informational text")
                //                case "Muted words":
                //                    MutedWordsView()
            default:
                BlockedAccounts()
            }
            Spacer()
        }
        .background(themes.theme.listBackground)
        .navigationTitle(tab)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BlockedAccounts:View {
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var la:LoggedInAccount
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt_, order: .reverse)], predicate: NSPredicate(format: "type_ == %@", CloudBlocked.BlockType.contact.rawValue))
    var blockedPubkeys:FetchedResults<CloudBlocked>
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(blockedPubkeys) { blockedPubkey in
                    if let contact = Contact.fetchByPubkey(blockedPubkey.pubkey, context: viewContext) {
                        ProfileRow(withoutFollowButton: true, contact: contact)
                            .background(themes.theme.background)
                            .onSwipe(tint: .green, label: "Unblock", icon: "figure.2.arms.open") {
                                let updatedList = blockedPubkeys
                                    .filter { $0.pubkey != blockedPubkey.pubkey }
                                    .map { $0.pubkey }
                                
                                viewContext.delete(blockedPubkey)
                                sendNotification(.blockListUpdated, Set(updatedList))
                            }
                    }
                    else {
                        HStack(alignment: .top) {
                            PFP(pubkey: blockedPubkey.pubkey)
                            VStack(alignment: .leading) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(blockedPubkey.fixedName).font(.headline).foregroundColor(.primary)
                                            .lineLimit(1)
                                    }
                                    .multilineTextAlignment(.leading)
                                    Spacer()
                                }
                            }
                        }
                        .padding()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            navigateTo(ContactPath(key: blockedPubkey.pubkey))
                        }
                        .background(themes.theme.background)
                        .onSwipe(tint: .green, label: "Unblock", icon: "figure.2.arms.open") {
                            let updatedList = blockedPubkeys
                                .filter { $0.pubkey != blockedPubkey.pubkey }
                                .map { $0.pubkey }
                            
                            viewContext.delete(blockedPubkey)
                            sendNotification(.blockListUpdated, Set(updatedList))
                        }
                    }
                }
            }
        }
    }
}

struct MutedConversations: View {
    @EnvironmentObject var themes: Themes
    @ObservedObject var settings:SettingsStore = .shared
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt_, order: .reverse)], predicate: NSPredicate(format: "type_ == %@", CloudBlocked.BlockType.post.rawValue))
    var mutedRootIds:FetchedResults<CloudBlocked>
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(mutedRootIds) { mutedRootId in
                    Box {
                        if let event = try? Event.fetchEvent(id: mutedRootId.eventId, context: viewContext) {
                            HStack(spacing: 10) {
                                PFP(pubkey: event.pubkey, contact: event.contact, size: 25)
                                    .onTapGesture {
                                        navigateTo(ContactPath(key: event.pubkey))
                                    }
                                MinimalNoteTextRenderViewText(plainText: event.plainText, lineLimit: 1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture { navigateTo(NotePath(id: event.id)) }
                            }
                        }
                        else {
                            HStack(spacing: 10) {
                                PFP(pubkey: mutedRootId.eventId, size: 25)
                                NRText("Can't find event id: \(note1(mutedRootId.eventId) ?? "?")")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture { navigateTo(NotePath(id: mutedRootId.eventId)) }
                            }
                        }
                    }
                    .id(mutedRootId.eventId)
                    .onSwipe(tint: Color.green, label: "Unmute", icon: "speaker.wave.1") {
                        viewContext.delete(mutedRootId)
                    }
                }
                Spacer()
            }
        }
    }
}

struct BlockListView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            VStack {
                BlockListView()
            }
        }
    }
}
