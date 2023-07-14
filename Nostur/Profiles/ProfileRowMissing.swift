//
//  ProfileRowMissing.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/02/2023.
//

import SwiftUI

struct ProfileRowMissing: View {
    
    var pubkey:String
    
    var body: some View {
        NavigationLink(value: ContactPath(key: pubkey)) {
            HStack(alignment: .top) {
                PFP(pubkey: pubkey)
                VStack(alignment: .leading) {
                    HStack {
                        VStack(alignment: .leading) {
                            HStack(spacing:3) {
                                Text(verbatim: "No kind 0 event").font(.headline).foregroundColor(.primary)
                                    .redacted(reason: .placeholder)
                                    .lineLimit(1)
                            }
                            
                            Text(verbatim: "@missing").font(.subheadline).foregroundColor(.secondary)
                                .redacted(reason: .placeholder)
                                .lineLimit(1)
                        }.multilineTextAlignment(.leading)
                        Spacer()
                    }
                    Text(verbatim:"").foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding()
            .contentShape(Rectangle())
            .onTapGesture {
                navigateTo(ContactPath(key: pubkey))
            }
        }
    }
}

struct ProfileRowMissing_Previews: PreviewProvider {
    static var previews: some View {
        ProfileRowMissing(pubkey: "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240")
    }
}
