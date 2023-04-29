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
            PFP(pubkey: contact.pubkey, pictureUrl: contact.picture, isFollowing: ns.isFollowing(contact.pubkey))
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {                        
                        HStack(spacing:3) {
                            Text(contact.authorName).font(.headline).foregroundColor(.primary)
                                .lineLimit(1)
                            
                            if (contact.nip05veried) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color("AccentColor"))
                            }
                        }
                        
                        Text("@\(contact.username)").font(.subheadline).foregroundColor(.secondary)
                            .lineLimit(1)
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
        
        // 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0 // bitcoiner
        // snowden: 84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240
        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
        
        let contact = PreviewFetcher.fetchContact(pubkey)
        
        VStack {
            ContactSearchResultRow(contact: contact!, onSelect: {})
            
            ContactSearchResultRow(contact: contact!, onSelect: {})
            
            ContactSearchResultRow(contact: contact!, onSelect: {})
         
            Spacer()
        }
        .withPreviewEnvironment()
        
    }
}
