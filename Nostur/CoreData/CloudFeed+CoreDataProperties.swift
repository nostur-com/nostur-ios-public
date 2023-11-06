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
    // "..more??" = ...
    @NSManaged public var type: String? // Use LVM.ListType enum
    @NSManaged public var wotEnabled: Bool
    @NSManaged public var pubkeys: String?
    @NSManaged public var relays: String?

}

extension CloudFeed : Identifiable {
    
    // MARK: DB functions
    static func fetchAll(context: NSManagedObjectContext) -> [CloudFeed] {
        let fr = CloudFeed.fetchRequest()
        return (try? context.fetch(fr)) ?? []
    }
    
    var followingHashtags:Set<String> {
        get {
            guard let followingHashtags_ else { return [] }
            return Set(followingHashtags_.split(separator: " ").map { String($0) })
        }
        set {
            followingHashtags_ = newValue.joined(separator: " ")
        }
    }
    
    var contacts_:[Contact] {
        get {
            guard let pubkeys = self.pubkeys?.components(separatedBy: " ") else { return [] }
            let context = Thread.isMainThread ? DataProvider.shared().viewContext : bg()
            return Contact.fetchByPubkeys(pubkeys, context: context)
        }
        set { self.pubkeys = newValue.map { $0.pubkey }.joined(separator: " ") }
    }
    
    var relays_:Set<Relay> {
        get {  
            let context = Thread.isMainThread ? DataProvider.shared().viewContext : bg()
            let relayUrls = Set(self.relays?.components(separatedBy: " ") ?? [])
            let fr = Relay.fetchRequest()
            fr.predicate = NSPredicate(value: true)
            let allRelays = (try? context.fetch(fr)) ?? []
            var relays:[Relay] = []
            var didAddNew = false
            for url in relayUrls {
                if let relay = allRelays.first(where: { $0.url == url || (($0.url ?? "") + "/") == url || $0.url == (url + "/") }) {
                    relays.append(relay)
                }
                else {
                    let newRelay = Relay(context: context)
                    newRelay.url = url
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
        set { self.relays = newValue.compactMap { $0.url }.joined(separator: " ") }
    }
    
    var name_:String {
        get { name ?? "" }
        set { name = newValue }
    }
    
    var subscriptionId:String {
        let id = id?.uuidString ?? "UNKNOWN"
        let idLength = id.count
        return ("List-" + String(id.prefix(min(idLength,18))))
    }
}
