//
//  ProfileRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/01/2023.
//

import SwiftUI

struct ProfileRow: View {
    let nav:NavigationModel = .shared
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var sp:SocketPool
//    var sp:SocketPool = .shared
    
    // Following/Unfollowing tap is slow so update UI and do in background:
    @State var isFollowing = false
    var withoutFollowButton = false
    
    @ObservedObject var contact:Contact
    
    var body: some View {
//        NavigationLink(value: contact) {
            HStack(alignment: .top) {
                ProfilePicView(pubkey: contact.pubkey, contact: contact)
                VStack(alignment: .leading) {
                    HStack {
                        VStack(alignment: .leading) {
                            HStack(spacing:3) {
                                Text(contact.authorName).font(.headline).foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                if (contact.nip05veried) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            Text("@\(contact.username)").font(.subheadline).foregroundColor(.secondary)
                                .lineLimit(1)
                        }.multilineTextAlignment(.leading)
                        Spacer()
                        if (!withoutFollowButton) {
                            Button {
                                if (isFollowing) {
                                    isFollowing = false
                                    ns.unfollow(contact)
                                }
                                else {
                                    print("chaning isFollowing to true 1")
                                    isFollowing = true
                                    ns.follow(contact)
                                    print("chaning isFollowing to true 2")
                                    //                                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: pubkey)))
                                }
                            } label: {
                                FollowButton(isFollowing:isFollowing)
                            }
                        }
                    }
                    Text(contact.about ?? "").foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                nav.navigateTo(contact)
            }
//        }
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
        
        VStack {
            ProfileRow(contact: contact!)
            
            ProfileRow(contact: contact!)
            
            ProfileRow(contact: contact!)
         
            Spacer()
        }
        .withPreviewEnvironment()
        
    }
}
