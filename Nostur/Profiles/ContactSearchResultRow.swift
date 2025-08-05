//
//  ContactSearchResultRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

import SwiftUI

struct ContactSearchResultRow: View {
    @Environment(\.theme) private var theme
    @ObservedObject var contact: Contact
    var onSelect: (() -> Void)?
    
    @State var similarToPubkey: String? = nil
    @State var isFollowing = false
    @State var fixedPfp: URL?
    
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
                        
                        if let similarToPubkey {
                            Text("possible imposter", comment: "Label shown on a profile").font(.system(size: 12.0))
                                .padding(.horizontal, 8)
                                .background(.red)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .padding(.top, 3)
                                .layoutPriority(2)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    sendNotification(.showImposterDetails, ImposterDetails(pubkey: contact.pubkey, similarToPubkey: similarToPubkey))
                                }
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
    @Environment(\.theme) private var theme
    @ObservedObject var nrContact: NRContact
    var onSelect: (() -> Void)?

    @State var isFollowing = false
    @State var fixedPfpURL: URL?

    
    var body: some View {
        HStack(alignment: .top) {
            PFP(pubkey: nrContact.pubkey, nrContact: nrContact)
                .overlay(alignment: .bottomTrailing) {
                    if let fixedPfpURL {
                        FixedPFP(picture: fixedPfpURL)
                    }
                }
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(nrContact.anyName)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        PossibleImposterLabelView2(nrContact: nrContact)
                        if nrContact.similarToPubkey == nil && nrContact.nip05verified, let nip05 = nrContact.nip05 {
                            NostrAddress(nip05: nip05, shortened: nrContact.anyName.lowercased() == nrContact.nip05nameOnly?.lowercased())
                                .layoutPriority(3)
                        }
                        
                        if let fixedName = nrContact.fixedName, fixedName != nrContact.anyName {
                            HStack {
                                Text("Previously known as: \(fixedName)").font(.caption).foregroundColor(.primary)
                                    .lineLimit(1)
                                Image(systemName: "multiply.circle.fill")
                                    .onTapGesture {
                                        nrContact.setFixedName(nrContact.anyName)
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
            if let fixedPfpURL = nrContact.fixedPfpURL,
               fixedPfpURL != nrContact.pictureUrl,
               hasFPFcacheFor(pfpImageRequestFor(fixedPfpURL))
            {
                withAnimation {
                    self.fixedPfpURL = fixedPfpURL
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
