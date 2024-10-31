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
public class CloudFeed: NSManagedObject {

    static func generateExamples(amount: Int = 10, context: NSManagedObjectContext) {
        let contacts = PreviewFetcher.allContacts(context: context)
        for i in 0..<amount {
            let feed = CloudFeed(context: context)
            feed.id = UUID()
            feed.type = ListType.pubkeys.rawValue
            feed.createdAt = .now
            feed.name = "Example Feed \(i)"
            feed.contactPubkeys = Set(contacts.randomSample(count: 10).map { $0.pubkey })
            feed.followingHashtags = ["bitcoin","nostr"]
            feed.showAsTab = true
            feed.wotEnabled = false
        }
    }
}
