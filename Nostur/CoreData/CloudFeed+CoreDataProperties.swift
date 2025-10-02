//
//  CloudFeed+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/11/2023.
//
//

import Foundation
import CoreData


extension CloudFeed {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CloudFeed> {
        return NSFetchRequest<CloudFeed>(entityName: "CloudFeed")
    }

    @NSManaged public var createdAt: Date?
    @NSManaged public var followingHashtags_: String?
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var refreshedAt: Date?
    @NSManaged public var showAsTab: Bool
    
    // default (nil) or "pubkeys" = feed of posts from selected pubkeys
    // "relays" = Relays feed. Any post from selected relays
    // "hashtags" = Feed of posts with selected hashtag(s) (TODO)
    // "following" = Feed of posts with selected hashtag(s)
    // "..more??" = ...
    @NSManaged public var type: String? // Use CloudFeedType enum
    @NSManaged public var wotEnabled: Bool
    
    // Continue Where Left Off toggle - Restore state / scroll position next time opening the feed. For relay feeds better default to off. For contact feeds turn on to catch up on missed posts
    @NSManaged public var `continue`: Bool
    @NSManaged public var pubkeys: String?
    @NSManaged public var relays: String?
    
    // Fields from old ListState migrated to CloudFeed
    
    @NSManaged public var updatedAt: Date?
    @NSManaged public var listId: String? // We can use this to store aTag for now
    @NSManaged public var repliesEnabled: Bool
    
    @NSManaged public var accountPubkey: String? // Feed "relays" type + accountPubkey = auth enabled
    
    @NSManaged public var profilesFetchedAt: Date? // use as "since" for checking new profiles for this feed
    
    @NSManaged public var lastRead_: String? // same as on CloudAccount
    @NSManaged public var order: Int16 // manual sorting order
    
    @NSManaged public var sharedList: Bool // for turning this list into a public kind:30000. Requires accountPubkey to be set
    @NSManaged public var sharedTitle: String? // Public title (title-tag), different from local title in tabs
}

extension CloudFeed : Identifiable {
    
    var aTag: ATag? {
        guard let listId else { return nil }
        guard let aTag = try? ATag(listId) else {
            return nil
        }
        return aTag
    }
    
    static func fetchAll(context: NSManagedObjectContext) -> [CloudFeed] {
        let fr = CloudFeed.fetchRequest()
        return (try? context.fetch(fr)) ?? []
    }
    
    var followingHashtags: Set<String> {
        get {
            guard let followingHashtags_ else { return [] }
            return Set(followingHashtags_.split(separator: " ").map { String($0) })
        }
        set {
            followingHashtags_ = newValue.joined(separator: " ")
        }
    }
    
    var contacts_: [Contact] {
        get {
            guard let pubkeys = self.pubkeys?.components(separatedBy: " ") else { return [] }
            let context = Thread.isMainThread ? DataProvider.shared().viewContext : bg()
            return Contact.fetchByPubkeys(pubkeys, context: context)
        }
        set { self.pubkeys = newValue.map { $0.pubkey }.joined(separator: " ") }
    }
    
    var contactPubkeys: Set<String> {
        get {
            guard let pubkeys else { return [] }
            return Set(pubkeys.split(separator: " ").map { String($0) })
        }
        set {
            pubkeys = newValue.joined(separator: " ")
        }
    }
    
    var relays_: Set<CloudRelay> {
        get {
            let context = Thread.isMainThread ? DataProvider.shared().viewContext : bg()
            let relayUrls = Set(self.relays?.components(separatedBy: " ") ?? [])
            let fr = CloudRelay.fetchRequest()
            fr.predicate = NSPredicate(value: true)
            let allRelays = (try? context.fetch(fr)) ?? []
            var relays: [CloudRelay] = []
            var didAddNew = false
            for url in relayUrls {
                if url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                if let relay = allRelays.first(where: { $0.url_ == url || (($0.url_ ?? "") + "/") == url || $0.url_ == (url + "/") }) {
                    relays.append(relay)
                }
                else {
                    let newRelay = CloudRelay(context: context)
                    newRelay.url_ = url
                    newRelay.write = false
                    newRelay.read = false
                    newRelay.createdAt = .now
                    didAddNew = true
                    relays.append(newRelay)
                }
            }
            if didAddNew {
                try? context.save()
            }
            return Set(relays)
        }
        set { self.relays = newValue.compactMap { $0.url_ }.joined(separator: " ") }
    }
    
    var name_: String {
        get { name ?? "" }
        set { name = newValue }
    }   
    var sharedTitle_: String {
        get { sharedTitle ?? "" }
        set { sharedTitle = newValue }
    }
    
    var subscriptionId: String {
        let id = id?.uuidString ?? "UNKNOWN"
        let idLength = id.count
        
        switch type {
        case "following":
            return ("Following-" + String(id.prefix(min(idLength,18))))
        case "pubkeys":
            return ("List-" + String(id.prefix(min(idLength,18))))
        case "relays":
            return ("List-" + String(id.prefix(min(idLength,18))))
            
        case "30000":
            return ("List-" + String(id.prefix(min(idLength,18))))
            
        default:
            return ("List-" + String(id.prefix(min(idLength,18))))
        }
    }
    
    var feedType: NXColumnType {
        switch type {
        case "following":
            .following(self)
        case "picture":
            .picture(self)
        case "pubkeys":
            .pubkeys(self)
        case "relays":
            .relays(self)
            
        // Nostr native lists
        case "30000":
            .followSet(self)
            
        // Nostr native lists
        case "39089":
            .followPack(self)
            
            
        default:
            .pubkeys(self)
        }
    }
    
    var relaysData: Set<RelayData> {
        Set(relays_.map { $0.toStruct() })
    }
    
    // helper to get account
    var account: CloudAccount? {
        guard let accountPubkey = self.accountPubkey,
              let account = AccountsState.shared.accounts.first(where: { $0.publicKey == accountPubkey })
        else { return nil }
        return account
    }
    
    // Short IDs (.prefix(8))
    public var lastRead: [String] {
        get {
            return lastRead_?.split(separator: " ").map { String($0) } ?? []
        }
        set {
            lastRead_ = newValue.joined(separator: " ")
        }
    }
}

public enum CloudFeedType: String, Identifiable, Hashable {
    case pubkeys = "pubkeys"
    case relays = "relays"
    case following = "following"
    case picture = "picture"
    case mentions = "mentions"
    case hashtags = "hashtags"
    
    // nostr native lists
    case followSet = "30000" // a "subscribed" follow set
    case followPack = "39089" // a "subscribed" follow pack

    public var id: String {
        String(self.rawValue)
    }
}
