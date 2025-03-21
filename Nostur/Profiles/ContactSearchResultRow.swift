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
        guard let la = AccountsState.shared.loggedInAccount else { return false }
        guard la.account.publicKey != contact.pubkey else { return false }
        guard !la.isFollowing(pubkey: contact.pubkey) else { return false }
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
                ImposterChecker.shared.runImposterCheck(contact: contact) { imposterYes in
                    self.similarPFP = true
                    self.similarToPubkey = imposterYes.similarToPubkey
                }
            }
            
            if let fixedPfp = contact.fixedPfp,
               fixedPfp != contact.picture,
               let fixedPfpUrl = URL(string: fixedPfp),
               hasFPFcacheFor(pfpImageRequestFor(fixedPfpUrl))
            {
                withAnimation {
                    self.fixedPfp = fixedPfpUrl
                }
            }
        }
    }
}

struct NRContactSearchResultRow: View {
    @EnvironmentObject private var themes: Themes
    @ObservedObject var nrContact: NRContact
    var onSelect: (() -> Void)?
    
    @State var similarPFP = false
    @State var similarToPubkey: String? = nil
    @State var isFollowing = false
    @State var fixedPfp: URL?
    
    var couldBeImposter: Bool {
        guard let la = AccountsState.shared.loggedInAccount else { return false }
        guard la.account.publicKey != nrContact.pubkey else { return false }
        guard !la.isFollowing(pubkey: nrContact.pubkey) else { return false }
        guard nrContact.couldBeImposter == -1 else { return nrContact.couldBeImposter == 1 }
        return similarPFP
    }
    
    var body: some View {
        HStack(alignment: .top) {
            PFP(pubkey: nrContact.pubkey, nrContact: nrContact)
                .overlay(alignment: .bottomTrailing) {
                    if let fixedPfp {
                        FixedPFP(picture: fixedPfp)
                    }
                }
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(nrContact.anyName)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if couldBeImposter {
                            PossibleImposterLabel(possibleImposterPubkey: nrContact.pubkey, followingPubkey: similarToPubkey ?? nrContact.similarToPubkey)
                        }
                        else if nrContact.nip05verified, let nip05 = nrContact.nip05 {
                            NostrAddress(nip05: nip05, shortened: nrContact.anyName.lowercased() == nrContact.nip05nameOnly.lowercased())
                                .layoutPriority(3)
                        }
                        
                        if let fixedName = nrContact.fixedName, fixedName != nrContact.anyName {
                            HStack {
                                Text("Previously known as: \(fixedName)").font(.caption).foregroundColor(.primary)
                                    .lineLimit(1)
                                Image(systemName: "multiply.circle.fill")
                                    .onTapGesture {
                                        nrContact.fixedName = nrContact.anyName
                                        bg().perform {
                                            nrContact.contact?.fixedName = nrContact.anyName
                                        }
                                    }
                            }
                        }
                    }
                    .multilineTextAlignment(.leading)
                    Spacer()
                }
                Text(nrContact.about ?? "").foregroundColor(.primary)
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
            isFollowing = Nostur.isFollowing(nrContact.pubkey)
        }
        .task { [weak nrContact] in
            guard let nrContact else { return }
            if (Nostur.isFollowing(nrContact.pubkey)) {
                isFollowing = true
            }
            else {
                ImposterChecker.shared.runImposterCheck(nrContact: nrContact) { imposterYes in
                    self.similarPFP = true
                    self.similarToPubkey = imposterYes.similarToPubkey
                }
            }
            
            if let fixedPfp = nrContact.fixedPfp,
               fixedPfp != nrContact.pictureUrl?.absoluteString,
               let fixedPfpUrl = URL(string: fixedPfp),
               hasFPFcacheFor(pfpImageRequestFor(fixedPfpUrl))
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
                if let nrContact = PreviewFetcher.fetchNRContact(pubkey) {
                    NRContactSearchResultRow(nrContact: nrContact, onSelect: {})
                    
                    NRContactSearchResultRow(nrContact: nrContact, onSelect: {})
                    
                    NRContactSearchResultRow(nrContact: nrContact, onSelect: {})
                }
             
                Spacer()
            }
        }
    }
}
