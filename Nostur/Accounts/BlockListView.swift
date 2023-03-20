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
            }
            switch tab {
                case "Blocked":
                    BlockedAccounts()
                case "Muted":
                    MutedConversations()
                default:
                    BlockedAccounts()
            }
            Text("Swipe to unblock/unmute")
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
        if (ns.account == nil) {
            Text("Please choose account first")
        }
        else {
            List {
                ForEach(blockedContacts.sorted(by: { $0.authorName < $1.authorName })) { contact in
                    ProfileRow(withoutFollowButton: true, contact: contact)
//                        .id(contact.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
//                                withAnimation {
                                ns.objectWillChange.send()
                                ns.account!.blockedPubkeys_.removeAll(where: { $0 == contact.pubkey })
                                try! viewContext.save()
                                do {
                                    try viewContext.save()
                                    sendNotification(.blockListUpdated, ns.account!.blockedPubkeys_)
                                } catch {
                                    print("🔴 could not remove contact from blocked list")
                                    print(error)
                                }
//                                }
                            } label: { Text("Unblock") }.tint(.green)
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
    }
}

struct MutedConversations: View {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(value: false))
    var mutedRootEvents:FetchedResults<Event>
    
    var vPosts:[VPost] {
        mutedRootEvents.map(VPostTransformer.shared.toVPost)
    }
    
    var body: some View {
        if (ns.account == nil) {
            Text("Please choose account first")
        }
        else {
            List {
                ForEach(vPosts) { vPost in
                    NoteRow(vPost: vPost)
                        .listRowInsets(EdgeInsets())
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                ns.objectWillChange.send()
                                ns.account!.mutedRootIds_.removeAll(where: { $0 == vPost.id })
                                do {
                                    try viewContext.save()
                                } catch {
                                    print("🔴 could not remove post from muted conversations")
                                    print(error)
                                }
                            } label: { Text("Unmute") }.tint(.green)
                        }
                }
            }
            .listStyle(.plain)
            .onAppear {
                if let account = ns.account {
                    mutedRootEvents.nsPredicate = NSPredicate(format: "id IN %@", account.mutedRootIds_)
                }
            }
            .onChange(of: ns.account!.mutedRootIds_) { newValue in
                mutedRootEvents.nsPredicate = NSPredicate(format: "id IN %@", newValue)
            }
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
