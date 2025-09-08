//
//  CloudFeed+CoreDataClass.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/11/2023.
//
//

import Foundation
import CoreData

@objc(CloudFeed)
public class CloudFeed: NSManagedObject, IdentifiableDestination {

    static func generateExamples(amount: Int = 10, context: NSManagedObjectContext) {
        
        // generate following feed
        let followingFeed = CloudFeed(context: context)
        followingFeed.id = UUID()
        followingFeed.type = "following"
        followingFeed.createdAt = .now
        followingFeed.name = "Following for PreviewCanvas"
        followingFeed.accountPubkey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
        followingFeed.contactPubkeys = []
        followingFeed.followingHashtags = ["bitcoin","nostr"]
        followingFeed.showAsTab = true
        followingFeed.wotEnabled = false
        followingFeed.order = 0
        
        // generate relay feed
        let relayfeed = CloudFeed(context: context)
        relayfeed.id = UUID()
        relayfeed.type = CloudFeedType.relays.rawValue
        relayfeed.createdAt = .now
        relayfeed.name = "wss://localhost"
        
        // auth to relay with
        relayfeed.accountPubkey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
        relayfeed.showAsTab = true
        relayfeed.wotEnabled = false
        relayfeed.order = 0
        
        // generate some random
        let contacts = PreviewFetcher.allContacts(context: context)
        for i in 0..<amount {
            let feed = CloudFeed(context: context)
            feed.id = UUID()
            feed.type = CloudFeedType.pubkeys.rawValue
            feed.createdAt = .now
            feed.name = "Example Feed \(i)"
            feed.contactPubkeys = Set(contacts.randomSample(count: 10).map { $0.pubkey })
            feed.followingHashtags = ["bitcoin","nostr"]
            feed.showAsTab = true
            feed.wotEnabled = false
            feed.order = 0
            feed.accountPubkey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e" // own managed list
        }
    }
}
