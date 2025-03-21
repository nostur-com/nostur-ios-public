//
//  NXColumnConfig.swift
//  Nosturix
//
//  Created by Fabian Lachman on 03/08/2024.
//

import Foundation

struct NXColumnConfig: Identifiable, Equatable {
    
    static func == (lhs: NXColumnConfig, rhs: NXColumnConfig) -> Bool {
        lhs.id == rhs.id
    }
    
    var id: String
    var columnType: NXColumnType?
    var accountPubkey: String?
    var name: String
    
    @MainActor
    var wotEnabled: Bool {
        get { feed?.wotEnabled ?? false }
        set { 
            feed?.wotEnabled = newValue
            DataProvider.shared().save()
        }
    }
    
    @MainActor
    var repliesEnabled: Bool {
        get { (feed?.repliesEnabled ?? false) }
        set {
            feed?.repliesEnabled = newValue
            DataProvider.shared().save()
        }
    }
    
    // helper to get feed (in enum)
    var feed: CloudFeed? {
        switch columnType {
        case .following(let feed):
            return feed
        case .pubkeys(let feed):
            return feed
        case .relays(let feed):
            return feed
        case .hashtags(let feed):
            return feed
        case .picture(let feed):
            return feed
        default:
            return nil
        }
    }
    
    // helper to get account
    var account: CloudAccount? {
        guard let accountPubkey = feed?.accountPubkey,
              let account = AccountsState.shared.accounts.first(where: { $0.publicKey == accountPubkey })
        else { return nil }
        return account
    }
    
    // Temporary for SomeoneElses feed
    var pubkeys: Set<String> = []
    var hashtags: Set<String> = []
    
    mutating func setPubkeys(_ newPubkeys: Set<String>) {
        pubkeys = newPubkeys
    }
    
    mutating func setHashtags(_ newHashtags: Set<String>) {
        hashtags = newHashtags
    }
}

enum NXColumnType {
    case following(CloudFeed) // kind:3 p + hashtags from CloudAccount.accountPubkey
    case pubkeys(CloudFeed) // input=specific pubkeys, no accountPubkey needed
    case pubkey // input=single pubkey - stalker
    case relays(CloudFeed)
    case hashtags(CloudFeed)
    case someoneElses(String) // pubkeys
    case picture(CloudFeed) // kind:20 from follows
    
    case mentions
    case newPosts
    case reactions
    case reposts
    case zaps
    case newFollowers
    
    case search
    
    case bookmarks
    case privateNotes
    
    case DMs
    
    case hot
    case discover
    case gallery
    case explore
    case articles
}
