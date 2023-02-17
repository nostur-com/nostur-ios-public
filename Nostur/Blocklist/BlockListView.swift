//
//  BlockListView.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/02/2023.
//

import SwiftUI

struct BlockListView: View {
    
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
                                ns.account!.removeFromBlockedContacts(contact)
                                ns.objectWillChange.send()
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

struct BlockListView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            BlockListView()
                .withPreviewEnvironment()
        }
    }
}
