//
//  NIP29EventContext+CoreDataProperties.swift
//  Nostur
//

import CoreData
import Foundation

extension NIP29EventContext {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<NIP29EventContext> {
        NSFetchRequest<NIP29EventContext>(entityName: "NIP29EventContext")
    }

    /// Unique per account + relay branch + event. An Event can therefore belong to multiple forks.
    @NSManaged public var contextKey: String
    /// Unique timeline key per account + relay + group id.
    @NSManaged public var addressKey: String
    @NSManaged public var accountPubkey: String
    @NSManaged public var relayURL: String
    @NSManaged public var groupId: String
    @NSManaged public var eventId: String
    @NSManaged public var createdAt: Int64
    @NSManaged public var receivedAt: Date
    @NSManaged public var kind: Int64

    static func makeAddressKey(accountPubkey: String, address: NIP29GroupAddress) -> String {
        makeKey([accountPubkey.lowercased(), address.relayURL, address.groupId])
    }

    static func makeContextKey(accountPubkey: String, address: NIP29GroupAddress, eventId: String) -> String {
        makeKey([accountPubkey.lowercased(), address.relayURL, address.groupId, eventId])
    }

    @discardableResult
    static func upsert(
        accountPubkey: String,
        address: NIP29GroupAddress,
        eventId: String,
        createdAt: Int64,
        kind: Int64,
        receivedAt: Date = .now,
        in context: NSManagedObjectContext
    ) -> NIP29EventContext {
        let key = makeContextKey(accountPubkey: accountPubkey, address: address, eventId: eventId)
        let request = fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "contextKey == %@", key)
        let value = (try? context.fetch(request).first) ?? NIP29EventContext(context: context)
        value.contextKey = key
        value.addressKey = makeAddressKey(accountPubkey: accountPubkey, address: address)
        value.accountPubkey = accountPubkey.lowercased()
        value.relayURL = address.relayURL
        value.groupId = address.groupId
        value.eventId = eventId
        value.createdAt = createdAt
        value.kind = kind
        value.receivedAt = receivedAt
        return value
    }

    static func timelineRequest(
        accountPubkey: String,
        address: NIP29GroupAddress,
        before: Int64? = nil,
        limit: Int = 100
    ) -> NSFetchRequest<NIP29EventContext> {
        let request = fetchRequest()
        let key = makeAddressKey(accountPubkey: accountPubkey, address: address)
        if let before {
            request.predicate = NSPredicate(format: "addressKey == %@ AND createdAt < %lld", key, before)
        }
        else {
            request.predicate = NSPredicate(format: "addressKey == %@", key)
        }
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(NIP29EventContext.createdAt), ascending: false),
            NSSortDescriptor(key: #keyPath(NIP29EventContext.eventId), ascending: false)
        ]
        request.fetchLimit = max(1, limit)
        request.fetchBatchSize = min(100, max(1, limit))
        return request
    }

    private static func makeKey(_ values: [String]) -> String {
        values.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
    }
}

extension NIP29EventContext: Identifiable {}
