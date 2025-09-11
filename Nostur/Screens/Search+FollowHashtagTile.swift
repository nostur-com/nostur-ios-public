//
//  Search+FollowHashtagTile.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/08/2023.
//

import SwiftUI

struct FollowHashtagTile: View {
    @Environment(\.theme) private var theme
    public var hashtag:String
    private var hashtagNormalized:String {
        hashtag.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    @ObservedObject public var account:CloudAccount
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
            .buttonStyle(NRButtonStyle(style: .borderedProminent))
        }
        .padding(10)
    }
    
    func follow(_ hashtag:String) {
        account.followingHashtags.insert(hashtag)
        account.publishNewContactList()
    }
    
    func unfollow(_ hashtag:String) {
        account.followingHashtags.remove(hashtag)
        account.publishNewContactList()
    }
}





struct FollowHashtagTile_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer() {
            if let account = account() {
                FollowHashtagTile(hashtag:"nostr", account: account)
            }
        }
    }
}
