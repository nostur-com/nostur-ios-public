//
//  NewFollowersNotificationView.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/06/2023.
//

import SwiftUI

struct NewFollowersNotificationView: View {
    @Environment(\.containerID) private var containerID
    public var notification: PersistentNotification
    
    private var notificationPubkeys: [String] {
        notification.content.split(separator: ",").map(String.init)
    }
    
    @State private var nrContacts: [NRContact] = []
    
    var body: some View {
        VStack(alignment: .leading) {
            ZStack(alignment: .leading) {
                ForEach(nrContacts.prefix(10).indices, id:\.self) { index in
                    ObservedPFP(nrContact: nrContacts[index])
                        .id(nrContacts[index].pubkey)
                        .onTapGesture {
                            navigateTo(ContactPath(key: nrContacts[index].pubkey, navigationTitle: nrContacts[index].anyName), context: containerID)
                        }
                        .zIndex(-Double(index))
                        .offset(x:Double(0 + (30*index)))
                        .overlay(alignment: .topLeading) {
                            if index == 0 {
                                PossibleImposterLabelView(nrContact: nrContacts[index])
                                    .lineLimit(1)
                                    .fixedSize()
                                    .offset(x: -10, y: -10)
                            }
                        }
                }
            }
            if let first = nrContacts.first {
                NowFollowingYouMessage(first: first, newFollowersCount: nrContacts.count)
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
        .overlay(alignment: .topTrailing) {
            Ago(notification.createdAt).layoutPriority(2)
                .foregroundColor(.gray)
        }
        .padding(10)
        .onAppear {
            loadPFPs()
        }
    }
    
    func loadPFPs() {
        let notificationPubkeys = notificationPubkeys
        bg().perform {
            let nrContacts = notificationPubkeys.prefix(10)
                .map { NRContact.instance(of: $0) }
            
            let missingPs = nrContacts.filter { $0.metadata_created_at == 0 }.map { $0.pubkey }
            QueuedFetcher.shared.enqueue(pTags: missingPs)
            Task { @MainActor in
                self.nrContacts = nrContacts
            }
        }
    }
}

struct NowFollowingYouMessage: View {
    @ObservedObject public var first: NRContact
    public let newFollowersCount: Int
    
    var body: some View {
        if newFollowersCount > 1 {
            Text("**\(first.anyName)** and \(newFollowersCount - 1) others are now following you")
        }
        else {
            Text("**\(first.anyName)** is now following you")
        }
    }
}

struct NewFollowersNotificationView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadNewFollowersNotification()
        }) {
            PreviewFeed {
                if let pNotification = PreviewFetcher.fetchPersistentNotification() {
                    Box {
                        NewFollowersNotificationView(notification: pNotification)
                    }
                }
            }
        }
    }
}
