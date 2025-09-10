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
    
    // Don't set id too long, because its also used for subscription ids and relays will fail if its too long
    var id: String
    var columnType: NXColumnType?
    var accountPubkey: String?
    var name: String
    
    @MainActor
    var wotEnabled: Bool {
        get { feed?.wotEnabled ?? false }
        set { 
            feed?.wotEnabled = newValue
            DataProvider.shared().saveToDiskNow(.viewContext)
        }
    }
    
    @MainActor
    var repliesEnabled: Bool {
        get { (feed?.repliesEnabled ?? false) }
        set {
            feed?.repliesEnabled = newValue
            DataProvider.shared().saveToDiskNow(.viewContext)
        }
    }
    
    @MainActor
    var `continue`: Bool {
        get {
            switch columnType {
            case .pubkeysPreview(_):
                return false
            case .someoneElses(_):
                return false
            case .relayPreview(_):
                return false
            default:
                return (feed?.`continue` ?? true)
            }
        }
        set {
            feed?.`continue` = newValue
            DataProvider.shared().saveToDiskNow(.viewContext)
        }
    }
    
    // helper to get feed (in enum)
    var feed: CloudFeed? {
        switch columnType {
        case .following(let feed):
            return feed
        case .pubkeys(let feed):
            return feed
        case .followSet(let feed):
            return feed
        case .followPack(let feed):
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
    
    // Temporary only for .someoneElses feed
    var _pubkeys: Set<String> = []
    
    var pubkeys: Set<String> {
        get {
            switch columnType {
            case .pubkeysPreview(let pubkeys): // pubkeys are in the .columnType enum
                return pubkeys
            case .following(let feed), .pubkeys(let feed), .picture(let feed), .followSet(let feed), .followPack(let feed): // pubkeys are in the CloudFeed
                return feed.contactPubkeys
            default: // pubkeys are in the NXColumnConfig
                return _pubkeys
            }
        }
        set {
            switch columnType {
            case .pubkeysPreview(_): // pubkeys are in the .columnType enum
                self.setPubkeys(newValue)
            case .following(let feed), .pubkeys(let feed), .picture(let feed), .followSet(let feed), .followPack(let feed): // pubkeys are in the CloudFeed
                feed.contactPubkeys = newValue
            default: // pubkeys are in the NXColumnConfig
                _pubkeys = newValue
            }
        }
    }
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
    
    case pubkeysPreview(Set<String>) // Preview of shared lists
    case followSet(CloudFeed) // Shared list subscribed to
    case followPack(CloudFeed) // Shared follow pack subscribed to
    
    
    case pubkey // input=single pubkey - stalker
    case relayPreview(RelayData) // Preview of a relay feed
    case relays(CloudFeed)
    case hashtags(CloudFeed)
    case someoneElses(String) // pubkey of whose feed
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
