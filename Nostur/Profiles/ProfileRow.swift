//
//  ProfileRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/01/2023.
//

import SwiftUI

struct ProfileRow: View {
    @EnvironmentObject var ns:NosturState
    let sp:SocketPool = .shared
     
    // Following/Unfollowing tap is slow so update UI and do in background:
    @State var isFollowing = false
    var withoutFollowButton = false
    @ObservedObject var contact:Contact
    
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
                    if (!withoutFollowButton) {
                        Button {
                            if (isFollowing && !contact.privateFollow) {
                                contact.privateFollow = true
                                ns.follow(contact)
                            }
                            else if (isFollowing && contact.privateFollow) {
                                isFollowing = false
                                contact.privateFollow = false
                                ns.unfollow(contact)
                            }
                            else {
                                isFollowing = true
                                ns.follow(contact)
                            }
                        } label: {
                            FollowButton(isFollowing:isFollowing, isPrivateFollowing:contact.privateFollow)
                        }
                    }
                }
                Text(contact.about ?? "").foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture {
            navigateTo(ContactPath(key: contact.pubkey))
        }
        .onAppear {
            if (ns.isFollowing(contact)) {
                isFollowing = true
            }
        }
    }
}

struct ProfileRow_Previews: PreviewProvider {
    static var previews: some View {
        
        // 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0 // bitcoiner
        // snowden: 84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240
        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
        
        let contact = PreviewFetcher.fetchContact(pubkey)
        
        ScrollView {
            LazyVStack {
                ProfileRow(contact: contact!)
                
                ProfileRow(contact: contact!)
                
                ProfileRow(contact: contact!)
             
                Spacer()
            }
        }
        .withPreviewEnvironment()
        
    }
}
