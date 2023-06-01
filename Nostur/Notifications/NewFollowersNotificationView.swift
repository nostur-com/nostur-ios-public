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
    @EnvironmentObject var ns:NosturState
    
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
                ForEach(contacts.indices, id:\.self) { index in
                    PFP(pubkey: contacts[index].pubkey, contact: contacts[index])
                        .id(contacts[index].pubkey)
                        .onTapGesture {
                            navigateTo(ContactPath(key: contacts[index].pubkey))
                        }
                        .zIndex(-Double(index))
                        .offset(x:Double(0 + (30*index)))
                }
            }
            if (contacts.count > 1) {
                Text("**\(contacts.first?.anyName ?? "???")** and \(contacts.count - 1) others are now following you")
                    
            }
            else {
                Text("**\(contacts.first?.anyName ?? "???")** is now following you")
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
        .overlay(alignment: .topTrailing) {
            Ago(notification.createdAt).layoutPriority(2)
                .foregroundColor(.gray)
        }
//        .onAppear {
//            self.fetchMissingEventContacts(events:Array(withoutDuplicates.prefix(10)))
//        }
    }
    
//    func fetchMissingEventContacts(events:[Event]) {
//        let pubkeys = pubkeys(events)
//        let contacts = Contact.fetchByPubkeys(pubkeys, context: viewContext)
//        let missingPubkeys = pubkeys.filter {
//            contacts.map { $0.pubkey }.firstIndex(of: $0) == nil
//        }
//        let emptyContactPubkeys = pubkeys
//            .compactMap { pubkey in
//                contacts.first(where: { $0.pubkey == pubkey })
//            }
//            .filter { $0.metadata_created_at == 0 }
//            .map { $0.pubkey }
//
//        guard (missingPubkeys + emptyContactPubkeys).count > 0 else { return }
//        print("Fetching  \((missingPubkeys + emptyContactPubkeys).count) missing or empty contacts")
//        QueuedFetcher.shared.enqueue(pTags:  missingPubkeys + emptyContactPubkeys)
//    }
}

struct NewFollowersNotificationView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            if let pNotification = PreviewFetcher.fetchPersistentNotification() {
                NewFollowersNotificationView(notification: pNotification)
                    .padding(10)
                    .background(Color.systemBackground)
                    .boxShadow()
                    .padding(.vertical, 10)
                    .padding(.horizontal, 10)
            }
        }
            .withPreviewEnvironment({ pe in
                pe.loadContacts()
                pe.loadNewFollowersNotification()
            })
    }
}
