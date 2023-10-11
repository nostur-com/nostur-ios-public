//
//  NewFollowersNotificationView.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/06/2023.
//

import SwiftUI

struct NewFollowersNotificationView: View {
    var notification:PersistentNotification
    @Environment(\.managedObjectContext) var viewContext
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Contact.metadata_created_at, ascending: false)], predicate: NSPredicate(value: false))
    var contacts:FetchedResults<Contact>
    
    init(notification:PersistentNotification) {
        self.notification = notification
        let fr = Contact.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.metadata_created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "pubkey IN %@", notification.content.split(separator: ","))
        _contacts = FetchRequest(fetchRequest: fr)
    }
    
    var body: some View {
        VStack(alignment:.leading) {
            ZStack(alignment:.leading) {
                ForEach(contacts.prefix(10).indices, id:\.self) { index in
                    PFP(pubkey: contacts[index].pubkey, contact: contacts[index])
                        .id(contacts[index].pubkey)
                        .onTapGesture {
                            navigateTo(ContactPath(key: contacts[index].pubkey, navigationTitle: contacts[index].anyName))
                        }
                        .zIndex(-Double(index))
                        .offset(x:Double(0 + (30*index)))
                }
            }
            if (contacts.count > 1) {
                Text("**\(contacts.first?.anyName ?? "???")** and \(contacts.count - 1) others are now following you", comment: "Message when (name) and X others are now following yoru")
                    
            }
            else {
                Text("**\(contacts.first?.anyName ?? "???")** is now following you", comment: "Message when (name) is now following you")
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
        .overlay(alignment: .topTrailing) {
            Ago(notification.createdAt).layoutPriority(2)
                .foregroundColor(.gray)
        }
        .padding(10)
    }
}

struct NewFollowersNotificationView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadNewFollowersNotification()
        }) {
            SmoothListMock {
                if let pNotification = PreviewFetcher.fetchPersistentNotification() {
                    Box {
                        NewFollowersNotificationView(notification: pNotification)
                    }
                }
            }
        }
    }
}
