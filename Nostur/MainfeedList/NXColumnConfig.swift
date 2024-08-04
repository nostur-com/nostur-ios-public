//
//  NXColumnConfig.swift
//  Nosturix
//
//  Created by Fabian Lachman on 03/08/2024.
//

import Foundation

struct NXColumnConfig: Identifiable {
    var id: String
    var columnType: NXColumnType?
    var accountPubkey: String?
    var hideReplies: Bool = false
}

enum NXColumnType {
    case following(CloudFeed) // kind:3 p + hashtags from CloudAccount.accountPubkey
//    case pubkeys2(Set<String>) // input=specific pubkeys, no CloudFeed needed
    case pubkeys(CloudFeed) // input=specific pubkeys, no accountPubkey needed
    case pubkey // input=single pubkey - stalker
    case relays(CloudFeed)
    case hashtags
    
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
