//
//  Search+FollowHashtagTile.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/08/2023.
//

import SwiftUI

struct FollowHashtagTile: View {
    public var hashtag:String
    @ObservedObject public var account:Account
    var body: some View {
        HStack {
            Text(String(format:"#%@", hashtag))
                .fontWeight(.bold)
                .lineLimit(1)
            Spacer()
            Group {
                if account.followingHashtags.contains(hashtag) {
                    Button("Unfollow") {
                        unfollow(hashtag)
                    }
                }
                else {
                    Button("Follow") {
                        follow(hashtag)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .roundedBoxShadow()
    }
    
    func follow(_ hashtag:String) {
        account.followingHashtags.insert(hashtag)
    }
    
    func unfollow(_ hashtag:String) {
        account.followingHashtags.remove(hashtag)
    }
}





struct FollowHashtagTile_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer() {
            if let account = NosturState.shared.account {
                FollowHashtagTile(hashtag:"nostr", account: account)
            }
        }
    }
}
