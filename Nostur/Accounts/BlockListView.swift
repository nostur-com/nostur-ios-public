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
    }
}

struct BlockedAccounts:View {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    var body: some View {
        if (ns.account == nil) {
            Text("Please choose account first")
        }
        else {
            List {
                ForEach((ns.account!.blockedContacts ?? Set<Contact>()).sorted(by: { $0.authorName < $1.authorName })) { contact in
                    ProfileRow(withoutFollowButton: true, contact: contact)
//                        .id(contact.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
//                                withAnimation {
                                ns.objectWillChange.send()
                                ns.account!.removeFromBlockedContacts(contact)
//                                ns.objectWillChange.send()
                                try! viewContext.save()
                                do {
                                    try viewContext.save()
                                    sendNotification(.blockListUpdated, ns.account!.blockedContacts ?? Set<Contact>())
                                } catch {
                                    print("🔴 could not remove contact from blocked list")
                                    print(error)
                                }
//                                }
                            } label: { Text("Unblock") }.tint(.green)
                        }
                }
            }
        }
    }
}

struct MutedConversations:View {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    var body: some View {
        if (ns.account == nil) {
            Text("Please choose account first")
        }
        else {
            List {
                ForEach(Array(ns.account!.mutedConversations_)) { rootEvent in
                    NoteRowView(event: rootEvent)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                ns.objectWillChange.send()
                                ns.account!.removeFromMutedConversations(rootEvent)
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
