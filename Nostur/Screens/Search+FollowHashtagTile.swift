//
//  Search+FollowHashtagTile.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/08/2023.
//

import SwiftUI

struct FollowHashtagTile: View {
    public var hashtag:String
    private var hashtagNormalized:String {
        hashtag.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    @ObservedObject public var account:Account
    var body: some View {
        HStack {
            Text(String(format:"#%@", hashtagNormalized))
                .fontWeight(.bold)
                .lineLimit(1)
            Spacer()
            Group {
                if account.followingHashtags.contains(hashtagNormalized) {
                    Button("Unfollow") {
                        unfollow(hashtagNormalized)
                    }
                }
                else {
                    Button("Follow") {
                        follow(hashtagNormalized)
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
        NosturState.shared.publishNewContactList()
    }
    
    func unfollow(_ hashtag:String) {
        account.followingHashtags.remove(hashtag)
        NosturState.shared.publishNewContactList()
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
