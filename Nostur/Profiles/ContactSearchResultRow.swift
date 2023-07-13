//
//  ContactSearchResultRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

import SwiftUI

struct ContactSearchResultRow: View {
    @ObservedObject var contact:Contact
    @EnvironmentObject var ns:NosturState
    var onSelect:(() -> Void)?
    
    var body: some View {
        HStack(alignment: .top) {
            PFP(pubkey: contact.pubkey, contact: contact)
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {                        
                        HStack(spacing:3) {
                            Text(contact.anyName).font(.headline).foregroundColor(.primary)
                                .lineLimit(1)
                            
                            if (contact.nip05veried) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color("AccentColor"))
                            }
                        }
                    }.multilineTextAlignment(.leading)
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
