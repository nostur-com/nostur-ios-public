//
//  ContactSearchResultRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

import SwiftUI

struct ContactSearchResultRow: View {
    @EnvironmentObject private var themes: Themes
    @ObservedObject var contact: Contact
    var onSelect: (() -> Void)?
    
    @State var similarPFP = false
    @State var similarToPubkey: String? = nil
    @State var isFollowing = false
    @State var fixedPfp: URL?
    
    var couldBeImposter: Bool {
        guard let account = account() else { return false }
        guard account.publicKey != contact.pubkey else { return false }
        guard !Nostur.isFollowing(contact.pubkey) else { return false }
        guard contact.couldBeImposter == -1 else { return contact.couldBeImposter == 1 }
        return similarPFP
    }
    
    var body: some View {
        HStack(alignment: .top) {
            PFP(pubkey: contact.pubkey, contact: contact)
                .overlay(alignment: .bottomTrailing) {
                    if let fixedPfp {
                        FixedPFP(picture: fixedPfp)
                    }
                }
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(contact.anyName)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if couldBeImposter {
                            PossibleImposterLabel(possibleImposterPubkey: contact.pubkey, followingPubkey: similarToPubkey ?? contact.similarToPubkey)
                        }
                        else if contact.nip05veried, let nip05 = contact.nip05 {
                            NostrAddress(nip05: nip05, shortened: contact.anyName.lowercased() == contact.nip05nameOnly.lowercased())
                                .layoutPriority(3)
                        }
                        
                        if let fixedName = contact.fixedName, fixedName != contact.anyName {
                            HStack {
                                Text("Previously known as: \(fixedName)").font(.caption).foregroundColor(.primary)
                                    .lineLimit(1)
                                Image(systemName: "multiply.circle.fill")
                                    .onTapGesture {
                                        contact.fixedName = contact.anyName
                                    }
                            }
                        }
                    }
                    .multilineTextAlignment(.leading)
                    Spacer()
                }
                Text(contact.about ?? "").foregroundColor(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let onSelect {
                onSelect()
            }
        }
        .onReceive(receiveNotification(.activeAccountChanged)) { _ in
            isFollowing = Nostur.isFollowing(contact.pubkey)
        }
        .task { [weak contact] in
            guard let contact else { return }
            if (Nostur.isFollowing(contact.pubkey)) {
                isFollowing = true
            }
            else {
                guard !SettingsStore.shared.lowDataMode else { return }
                guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
                guard contact.metadata_created_at != 0 else { return }
                guard contact.couldBeImposter == -1 else { return }
                guard contact.picture != nil, let cPic = contact.pictureUrl else { return }
                guard !NewOnboardingTracker.shared.isOnboarding else { return }
                guard let followingCache = NRState.shared.loggedInAccount?.followingCache else { return }
                
                let contactAnyName = contact.anyName.lowercased()
                let cPubkey = contact.pubkey
                let currentAccountPubkey = NRState.shared.activeAccountPublicKey
                
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
                            guard currentAccountPubkey == NRState.shared.activeAccountPublicKey else { return }
                            self.similarPFP = similarPFP
                            self.similarToPubkey = followingPubkey
                            contact.couldBeImposter = similarPFP ? 1 : 0
                            contact.similarToPubkey = similarPFP ? followingPubkey : nil
                        }
                    }
                }
            }
            
            if let fixedPfp = contact.fixedPfp,
                fixedPfp != contact.picture,
               let fixedPfpUrl = URL(string: fixedPfp),
               hasFPFcacheFor(pfpImageRequestFor(fixedPfpUrl, size: 20.0))
            {
                withAnimation {
                    self.fixedPfp = fixedPfpUrl
                }
            }
        }
    }
}


struct ContactSearchResultRow_Previews: PreviewProvider {
    static var previews: some View {
        
        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
        
        PreviewContainer({ pe in
            pe.loadContacts()
        }) {
            VStack {
                if let contact = PreviewFetcher.fetchContact(pubkey) {
                    ContactSearchResultRow(contact: contact, onSelect: {})
                    
                    ContactSearchResultRow(contact: contact, onSelect: {})
                    
                    ContactSearchResultRow(contact: contact, onSelect: {})
                }
             
                Spacer()
            }
        }
    }
}
