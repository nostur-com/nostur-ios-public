//
//  NewFollowersNotificationView.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/06/2023.
//

import SwiftUI

struct NewFollowersNotificationView: View {
    public var notification: PersistentNotification
    
    private var notificationPubkeys: [String] {
        notification.content.split(separator: ",").map(String.init)
    }
    
    @State private var pfps: [PFPAttributes] = []
    @State private var followingNotificationText: String = ""
    
    @State private var similarPFP = false
    @State private var similarToPubkey: String? = nil
    @State private var didCheck = false
    
    var body: some View {
        VStack(alignment: .leading) {
            ZStack(alignment: .leading) {
                ForEach(pfps.prefix(10).indices, id:\.self) { index in
                    ObservedPFP(pfp: pfps[index])
                        .id(pfps[index].pubkey)
                        .onTapGesture {
                            navigateTo(ContactPath(key: pfps[index].pubkey, navigationTitle: pfps[index].anyName), context: "Default")
                        }
                        .zIndex(-Double(index))
                        .offset(x:Double(0 + (30*index)))
                        .overlay(alignment: .topLeading) {
                            if index == 0 {
                                NewPossibleImposterLabel(pfp: pfps[index])
                                    .lineLimit(1)
                                    .fixedSize()
                                    .offset(x: -10, y: -10)
                            }
                        }
                }
            }
            if let first = pfps.first {
                NowFollowingYouMessage(first: first, newFollowersCount: pfps.count)
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
            let pfps = notificationPubkeys.prefix(10)
                .map { pubkey in
                    if let nrContact = NRContact.fetch(pubkey) {
                        return PFPAttributes(contact: nrContact, pubkey: pubkey)
                    }
                    else {
                        return PFPAttributes(pubkey: pubkey)
                    }
                }
            
            let missingPs = pfps.filter { $0.contact == nil || $0.contact?.metadata_created_at == 0 }.map { $0.pubkey }
            QueuedFetcher.shared.enqueue(pTags: missingPs)
            Task { @MainActor in
                self.pfps = pfps
            }
        }
    }
}

struct NowFollowingYouMessage: View {
    @ObservedObject public var first: PFPAttributes
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
