//
//  CloudFeed+CoreDataClass.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/11/2023.
//
//

import Foundation
import CoreData
import CryptoKit

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
        // Resume Where Left: Default on for contact-based. Default off for relay-based
        followingFeed.continue = true
        
        // generate following feed
        let picturefeed = CloudFeed(context: context)
        picturefeed.id = UUID()
        picturefeed.type = "picture"
        picturefeed.createdAt = .now
        picturefeed.name = "📸"
        picturefeed.accountPubkey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
        picturefeed.contactPubkeys = []
        picturefeed.showAsTab = true
        picturefeed.wotEnabled = false
        picturefeed.order = 0
        // Resume Where Left: Default on for contact-based. Default off for relay-based
        picturefeed.continue = true
        
        // generate relay feed
        let relayfeed = CloudFeed(context: context)
        relayfeed.id = UUID()
        relayfeed.type = CloudFeedType.relays.rawValue
        relayfeed.createdAt = .now
        relayfeed.name = "wss://localhost"
        // Resume Where Left: Default on for contact-based. Default off for relay-based
        relayfeed.continue = false
        
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
            // Resume Where Left: Default on for contact-based. Default off for relay-based
            feed.continue = true
        }
    }
}

// A value snapshot is intentional here. Comparing two NSManagedObject references after a
// Core Data merge does not detect property changes because both references expose the new
// values. SwiftUI and NXColumnConfig use this snapshot to observe the values which actually
// affect a feed's UI and subscription.
struct CloudFeedChangeToken: Equatable {
    let objectID: NSManagedObjectID
    let id: UUID?
    let type: String?
    let accountPubkey: String?
    let name: String?
    let listId: String?
    let pubkeys: String?
    let relays: String?
    let kinds: String?
    let followingHashtags: String?
    let showAsTab: Bool
    let order: Int16
    let repliesEnabled: Bool
    let wotEnabled: Bool
    let continueEnabled: Bool
    let useOutbox: Bool

    init(_ feed: CloudFeed) {
        objectID = feed.objectID
        id = feed.id
        type = feed.type
        accountPubkey = feed.accountPubkey
        name = feed.name
        listId = feed.listId
        pubkeys = feed.pubkeys
        relays = feed.relays
        kinds = feed.kinds_
        followingHashtags = feed.followingHashtags_
        showAsTab = feed.showAsTab
        order = feed.order
        repliesEnabled = feed.repliesEnabled
        wotEnabled = feed.wotEnabled
        continueEnabled = feed.continue
        useOutbox = feed.useOutbox
    }
}

extension CloudFeed {
    static let defaultVineRelay = "wss://relay.divine.video"

    var changeToken: CloudFeedChangeToken { CloudFeedChangeToken(self) }

    /// Records an intentional settings change. Read/fetch progress must not update this value:
    /// it is used to resolve configuration conflicts between duplicate CloudKit records.
    func markUserEdited() {
        updatedAt = .now
    }

    private static let accountFeedTypes: Set<String> = [
        CloudFeedType.following.rawValue,
        CloudFeedType.picture.rawValue,
        CloudFeedType.yak.rawValue,
        CloudFeedType.vine.rawValue
    ]

    /// Returns one stable CloudFeed for an account-backed built-in feed. Multiple devices can
    /// create the feed before CloudKit has imported the other device's record, so logical
    /// identity is `(type, accountPubkey)`, not the Core Data object or its UUID alone.
    @discardableResult
    static func reconciledAccountFeed(
        type: CloudFeedType,
        accountPubkey: String,
        accountName: String,
        context: NSManagedObjectContext
    ) -> (feed: CloudFeed, didChange: Bool) {
        var didChange = reconcileDuplicates(in: context)
        let request = CloudFeed.fetchRequest()
        request.predicate = NSPredicate(
            format: "type == %@ AND accountPubkey == %@",
            type.rawValue,
            accountPubkey
        )

        if let feed = try? context.fetch(request).first {
            // Added with configurable media discovery sources. Preserve an explicitly empty
            // relay selection, but backfill legacy Vine feeds which predate the default.
            if type == .vine && feed.relays == nil {
                feed.relays = defaultVineRelay
                didChange = true
            }
            return (feed, didChange)
        }

        let feed = CloudFeed(context: context)
        feed.id = deterministicAccountFeedID(type: type, accountPubkey: accountPubkey)
        feed.createdAt = .now
        feed.type = type.rawValue
        feed.accountPubkey = accountPubkey
        feed.showAsTab = false
        feed.order = 0
        feed.wotEnabled = false

        switch type {
        case .following:
            feed.name = accountPubkey == EXPLORER_PUBKEY ? "Explore feed" : "Following for \(accountName)"
            feed.continue = true
        case .picture, .yak:
            feed.name = "\(feed.feedTitle()) for \(accountName)"
            feed.repliesEnabled = false
            feed.continue = false
        case .vine:
            feed.name = "\(feed.feedTitle()) for \(accountName)"
            feed.relays = defaultVineRelay
            feed.repliesEnabled = false
            feed.continue = false
        default:
            break
        }

        didChange = true
        return (feed, didChange)
    }

    /// Reconciles duplicate CloudKit records without relying on a view-specific fetch request.
    /// Custom feeds use their UUID as logical identity; built-in account feeds use type+pubkey.
    @discardableResult
    static func reconcileDuplicates(in context: NSManagedObjectContext) -> Bool {
        let request = CloudFeed.fetchRequest()
        guard let feeds = try? context.fetch(request) else { return false }
        var didChange = false
        var groups: [String: [CloudFeed]] = [:]

        for feed in feeds {
            if feed.id == nil {
                feed.id = UUID()
                didChange = true
            }

            let key: String
            if let type = feed.type,
               accountFeedTypes.contains(type),
               let accountPubkey = feed.accountPubkey,
               !accountPubkey.isEmpty {
                key = "account:\(type):\(accountPubkey)"
            }
            else {
                key = "id:\(feed.id!.uuidString)"
            }
            groups[key, default: []].append(feed)
        }

        for duplicates in groups.values where duplicates.count > 1 {
            let sorted = duplicates.sorted(by: canonicalFeedComesFirst)
            guard let canonical = sorted.first else { continue }
            for duplicate in sorted.dropFirst() {
                mergeSyncState(from: duplicate, into: canonical)
                context.delete(duplicate)
                didChange = true
            }
        }

        return didChange
    }

    private static func canonicalFeedComesFirst(_ lhs: CloudFeed, _ rhs: CloudFeed) -> Bool {
        // Explicit user edits win. Reading activity is deliberately excluded: progress is merged
        // separately and should never overwrite a feed configuration chosen on another device.
        if lhs.updatedAt != rhs.updatedAt {
            return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
        }

        // Legacy records did not consistently set updatedAt. Prefer a configured record over a
        // newly-created default so a relay choice or toggle is not lost during deduplication.
        let lhsConfigurationScore = configurationScore(lhs)
        let rhsConfigurationScore = configurationScore(rhs)
        if lhsConfigurationScore != rhsConfigurationScore {
            return lhsConfigurationScore > rhsConfigurationScore
        }

        // Otherwise retain the established record. This also preserves device-local state keyed
        // by its UUID, such as mediaFeedSource and lastLocalFetchAt.
        if lhs.createdAt != rhs.createdAt {
            return (lhs.createdAt ?? .distantFuture) < (rhs.createdAt ?? .distantFuture)
        }
        return lhs.objectID.uriRepresentation().absoluteString < rhs.objectID.uriRepresentation().absoluteString
    }

    private static func configurationScore(_ feed: CloudFeed) -> Int {
        var score = 0

        if feed.showAsTab { score += 1 }
        if feed.order != 0 { score += 1 }
        if feed.repliesEnabled { score += 1 }
        if feed.wotEnabled { score += 1 }
        if feed.useOutbox { score += 1 }
        if feed.pubkeys != nil { score += 1 }
        if feed.kinds_ != nil { score += 1 }
        if feed.followingHashtags_ != nil { score += 1 }
        if feed.listId != nil { score += 1 }

        switch feed.type.flatMap(CloudFeedType.init(rawValue:)) {
        case .following:
            if !feed.continue { score += 1 }
            if feed.relays != nil { score += 1 }
        case .vine:
            if feed.continue { score += 1 }
            if let relays = feed.relays, relays != defaultVineRelay { score += 1 }
        case .picture, .yak:
            if feed.continue { score += 1 }
            if feed.relays != nil { score += 1 }
        default:
            if feed.relays != nil { score += 1 }
        }

        return score
    }

    private static func mergeSyncState(from source: CloudFeed, into destination: CloudFeed) {
        // lastRead is newest-first. Start with the record whose read watermark is newest so the
        // 700-item cap discards the least useful history rather than whichever duplicate lost.
        let readStateNewestFirst = [destination, source].sorted {
            ($0.newestMarkedReadAt ?? .distantPast) > ($1.newestMarkedReadAt ?? .distantPast)
        }
        var mergedLastRead: [String] = []
        mergedLastRead.reserveCapacity(min(700, destination.lastRead.count + source.lastRead.count))
        var seen = Set(mergedLastRead)
        for feed in readStateNewestFirst {
            for id in feed.lastRead where seen.insert(id).inserted {
                mergedLastRead.append(id)
                if mergedLastRead.count == 700 { break }
            }
            if mergedLastRead.count == 700 { break }
        }
        destination.lastRead = mergedLastRead
        destination.createdAt = [destination.createdAt, source.createdAt].compactMap { $0 }.min()
        destination.newestMarkedReadAt = [destination.newestMarkedReadAt, source.newestMarkedReadAt].compactMap { $0 }.max()
        destination.profilesFetchedAt = [destination.profilesFetchedAt, source.profilesFetchedAt].compactMap { $0 }.max()
        destination.updatedAt = [destination.updatedAt, source.updatedAt].compactMap { $0 }.max()

        // Recover useful values from partially-created/imported records without replacing the
        // canonical record's user settings.
        if destination.name == nil { destination.name = source.name }
        if destination.pubkeys == nil { destination.pubkeys = source.pubkeys }
        if destination.relays == nil { destination.relays = source.relays }
        if destination.kinds_ == nil { destination.kinds_ = source.kinds_ }
        if destination.followingHashtags_ == nil { destination.followingHashtags_ = source.followingHashtags_ }
        if destination.listId == nil { destination.listId = source.listId }
    }

    private static func deterministicAccountFeedID(type: CloudFeedType, accountPubkey: String) -> UUID {
        let digest = SHA256.hash(data: Data("nostur-account-feed:\(type.rawValue):\(accountPubkey)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50 // UUID v5-style stable identifier
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let uuidString = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
        return UUID(uuidString: uuidString)!
    }
}
