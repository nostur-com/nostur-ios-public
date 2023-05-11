//
//  BlockListView.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/02/2023.
//

import SwiftUI

struct BlockListView: View {

    @State var tab = "Blocked"
    
    var body: some View {
        VStack {
            HStack {
                TabButton(action: {
                        tab = "Blocked"
                }, title: "Blocked", selected: tab == "Blocked")
                
                TabButton(action: {
                        tab = "Muted"
                }, title: "Muted conversations", selected: tab == "Muted")
//                TabButton(action: {
//                        tab = "Muted words"
//                }, title: "Muted words", selected: tab == "Muted words")
            }
            switch tab {
                case "Blocked":
                    BlockedAccounts()
                    Text("Swipe to unblock/unmute")
                case "Muted":
                    MutedConversations()
                    Text("Swipe to unblock/unmute")
//                case "Muted words":
//                    MutedWordsView()
                default:
                    BlockedAccounts()
            }
            Spacer()
        }
        .navigationTitle(tab)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BlockedAccounts:View {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(value: false))
    var blockedContacts:FetchedResults<Contact>
    
    var body: some View {
        if let account = ns.account {
            ScrollView {
                LazyVStack {
                    ForEach(blockedContacts.sorted(by: { $0.authorName < $1.authorName })) { contact in
                        ProfileRow(withoutFollowButton: true, contact: contact)
                            .onSwipe(tint: .green, label: "Unblock", icon: "") {
                                ns.objectWillChange.send()
                                account.blockedPubkeys_.removeAll(where: { $0 == contact.pubkey })
                                DataProvider.shared().save()
                                sendNotification(.blockListUpdated, account.blockedPubkeys_)
                            }
                        Divider()
                    }
                }
            }
            .onAppear {
                if let account = ns.account {
                    blockedContacts.nsPredicate = NSPredicate(format: "pubkey IN %@", account.blockedPubkeys_)
                }
            }
            .onChange(of: ns.account!.blockedPubkeys_) { newValue in
                blockedContacts.nsPredicate = NSPredicate(format: "pubkey IN %@", newValue)
            }
        }
        else {
            Text("Please choose account first")
        }
    }
}

struct MutedConversations: View {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(value: false))
    var mutedRootEvents:FetchedResults<Event>
    
    var vPosts:[VPost] {
        mutedRootEvents.compactMap { VPostTransformer.shared.toVPost($0, skipParents: true) }
    }
    
    var body: some View {
        if let account = ns.account {
            ScrollView {
                ForEach(vPosts) { vPost in
                    PostRowDeletable(vPost: vPost)
                        .onSwipe(tint: Color.green, label: "Unmute", icon: "") {
                            ns.objectWillChange.send()
                            account.mutedRootIds_.removeAll(where: { $0 == vPost.id })
                            DataProvider.shared().save()
                        }
                    Divider()
                }
            }
            .onAppear {
                mutedRootEvents.nsPredicate = NSPredicate(format: "id IN %@", account.mutedRootIds_)
            }
            .onChange(of: account.mutedRootIds_) { newValue in
                mutedRootEvents.nsPredicate = NSPredicate(format: "id IN %@", newValue)
            }
        }
        else {
            Text("Please choose account first")
        }
    }
}

struct BlockListView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            BlockListView()
                .withPreviewEnvironment()
        }
    }
}
