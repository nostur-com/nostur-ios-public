//
//  CloudNIP29GroupRelay+CoreDataProperties.swift
//  Nostur
//

import CoreData
import Foundation

extension CloudNIP29GroupRelay {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CloudNIP29GroupRelay> {
        NSFetchRequest<CloudNIP29GroupRelay>(entityName: "CloudNIP29GroupRelay")
    }

    @NSManaged public var id_: UUID?
    /// Foreign-key style identity avoids cross-store relationships and CloudKit relationship conflicts.
    @NSManaged public var familyId_: UUID?
    @NSManaged public var accountPubkey_: String?
    @NSManaged public var groupId_: String?
    @NSManaged public var relayURL_: String?
    @NSManaged public var sourceRelayURL_: String?
    @NSManaged public var createdAt_: Date?
    @NSManaged public var updatedAt_: Date?
    @NSManaged public var joinedAt_: Date?
    @NSManaged public var lastVisitedAt_: Date?
    @NSManaged public var isFork: Bool
    @NSManaged public var isArchived: Bool

    var address: NIP29GroupAddress? {
        guard let relayURL = relayURL_, let groupId = groupId_, !groupId.isEmpty else { return nil }
        return NIP29GroupAddress(relayURL: relayURL, groupId: groupId)
    }

    static func create(
        familyId: UUID,
        accountPubkey: String,
        address: NIP29GroupAddress,
        sourceRelayURL: String?,
        isFork: Bool,
        in context: NSManagedObjectContext
    ) -> CloudNIP29GroupRelay {
        let now = Date.now
        let relay = CloudNIP29GroupRelay(context: context)
        relay.id_ = UUID()
        relay.familyId_ = familyId
        relay.accountPubkey_ = accountPubkey.lowercased()
        relay.groupId_ = address.groupId
        relay.relayURL_ = address.relayURL
        relay.sourceRelayURL_ = sourceRelayURL.map(normalizeRelayUrl)
        relay.createdAt_ = now
        relay.updatedAt_ = now
        relay.joinedAt_ = now
        relay.lastVisitedAt_ = now
        relay.isFork = isFork
        relay.isArchived = false
        return relay
    }

    static func fetch(
        familyId: UUID,
        address: NIP29GroupAddress,
        in context: NSManagedObjectContext
    ) -> CloudNIP29GroupRelay? {
        let request = fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(
            format: "familyId_ == %@ AND relayURL_ == %@ AND groupId_ == %@",
            familyId as NSUUID,
            address.relayURL,
            address.groupId
        )
        return try? context.fetch(request).first
    }

    static func fetchAll(familyId: UUID, in context: NSManagedObjectContext) -> [CloudNIP29GroupRelay] {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "familyId_ == %@", familyId as NSUUID)
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(CloudNIP29GroupRelay.isArchived), ascending: true),
            NSSortDescriptor(key: #keyPath(CloudNIP29GroupRelay.lastVisitedAt_), ascending: false)
        ]
        return (try? context.fetch(request)) ?? []
    }
}

extension CloudNIP29GroupRelay: Identifiable {}
