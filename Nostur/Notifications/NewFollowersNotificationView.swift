//
//  NewFollowersNotificationView.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/06/2023.
//

import SwiftUI

struct NewFollowersNotificationView: View {
    var notification: PersistentNotification
    @Environment(\.managedObjectContext) var viewContext
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Contact.metadata_created_at, ascending: false)], predicate: NSPredicate(value: false))
    var contacts: FetchedResults<Contact>
    
    @State private var similarPFP = false
    @State private var similarToPubkey: String? = nil
    @State private var didCheck = false
    
    init(notification: PersistentNotification) {
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
                        .overlay(alignment: .topLeading) {
                            if index == 0 && (similarPFP || contacts[index].couldBeImposter == 1) {
                                PossibleImposterLabel(possibleImposterPubkey: contacts[index].pubkey, followingPubkey: contacts[index].similarToPubkey)
                                    .lineLimit(1)
                                    .fixedSize()
                                    .offset(x: -10, y: -10)
                            }
                        }
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
        .onAppear {
            // Check if first could be imposter
            self.checkIfFirstNameIsImposter()
        }
    }
    
    func checkIfFirstNameIsImposter() {
        // TODO: All imposter checker code is copy pasted in 10 places, need to make 1 reusable func
        guard !didCheck else { return }
        guard contacts.count > 0 else { return }
        let contact = contacts[0]
        guard !Nostur.isFollowing(contact.pubkey) else { return }
        guard !SettingsStore.shared.lowDataMode else { return }
        guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
        guard contact.metadata_created_at != 0 else { return }
        guard contact.couldBeImposter == -1 else { return }
        guard contact.picture != nil, let cPic = contact.pictureUrl else { return }
        guard !NewOnboardingTracker.shared.isOnboarding else { return }
        guard let followingCache = AccountsState.shared.loggedInAccount?.followingCache else { return }
        
        let contactAnyName = contact.anyName.lowercased()
        let cPubkey = contact.pubkey
        let currentAccountPubkey = AccountsState.shared.activeAccountPublicKey
        
        bg().perform { [weak contact] in
            guard let account = account() else { return }
            guard account.publicKey == currentAccountPubkey else { return }
            guard let (followingPubkey, similarFollow) = followingCache.first(where: { (pubkey: String, follow: FollowCache) in
                pubkey != cPubkey && isSimilar(string1: follow.anyName.lowercased(), string2: contactAnyName)
            }) else { return }
            
            guard similarFollow.pfpURL != nil, let wotPic = similarFollow.pfpURL else { return }
            
            L.og.debug("😎 ImposterChecker similar name: \(contactAnyName) - \(similarFollow.anyName)")
            
            Task.detached(priority: .background) {
                let similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                if similarPFP {
                    L.og.debug("😎 ImposterChecker similar PFP: \(cPic) - \(wotPic) - \(cPubkey)")
                }
                
                DispatchQueue.main.async {
                    guard let contact else { return }
                    guard currentAccountPubkey == AccountsState.shared.activeAccountPublicKey else { return }
                    self.similarPFP = similarPFP
                    self.similarToPubkey = followingPubkey
                    contact.couldBeImposter = similarPFP ? 1 : 0
                    contact.similarToPubkey = similarPFP ? followingPubkey : nil
                }
            }
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
