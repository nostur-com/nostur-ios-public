//
//  CloudNIP29Group+CoreDataProperties.swift
//  Nostur
//

import CoreData
import Foundation

extension CloudNIP29Group {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CloudNIP29Group> {
        NSFetchRequest<CloudNIP29Group>(entityName: "CloudNIP29Group")
    }

    /// Stable Nostur identity for a logical group across relay continuations and forks.
    @NSManaged public var id_: UUID?
    @NSManaged public var accountPubkey_: String?
    @NSManaged public var groupId_: String?
    @NSManaged public var activeRelayURL_: String?
    @NSManaged public var createdAt_: Date?
    @NSManaged public var updatedAt_: Date?
    @NSManaged public var joinedAt_: Date?
    @NSManaged public var markedReadAt_: Date?
    @NSManaged public var importedFromEventId_: String?
    @NSManaged public var state_: Int16
    @NSManaged public var isPinned: Bool
    @NSManaged public var sortOrder: Int32

    var persistedState: NIP29PersistedGroupState {
        get { NIP29PersistedGroupState(rawValue: state_) ?? .active }
        set { state_ = newValue.rawValue }
    }

    var familyId: UUID {
        if let id_ { return id_ }
        let value = UUID()
        id_ = value
        return value
    }

    var activeAddress: NIP29GroupAddress? {
        guard let relayURL = activeRelayURL_, let groupId = groupId_, !groupId.isEmpty else { return nil }
        return NIP29GroupAddress(relayURL: relayURL, groupId: groupId)
    }

    @discardableResult
    static func create(
        accountPubkey: String,
        address: NIP29GroupAddress,
        importedFromEventId: String? = nil,
        in context: NSManagedObjectContext
    ) -> (group: CloudNIP29Group, relay: CloudNIP29GroupRelay) {
        let now = Date.now
        let group = CloudNIP29Group(context: context)
        group.id_ = UUID()
        group.accountPubkey_ = accountPubkey.lowercased()
        group.groupId_ = address.groupId
        group.activeRelayURL_ = address.relayURL
        group.createdAt_ = now
        group.updatedAt_ = now
        group.joinedAt_ = now
        group.importedFromEventId_ = importedFromEventId
        group.persistedState = .active

        let relay = CloudNIP29GroupRelay.create(
            familyId: group.familyId,
            accountPubkey: accountPubkey,
            address: address,
            sourceRelayURL: nil,
            isFork: false,
            in: context
        )
        return (group, relay)
    }

    /// Adds a continuation or fork without deleting the old branch.
    @discardableResult
    func continueOnRelay(
        _ relayURL: String,
        asFork: Bool,
        in context: NSManagedObjectContext
    ) -> CloudNIP29GroupRelay? {
        guard let accountPubkey = accountPubkey_,
              let groupId = groupId_,
              let oldRelayURL = activeRelayURL_ else { return nil }

        let address = NIP29GroupAddress(relayURL: relayURL, groupId: groupId)
        let relay = CloudNIP29GroupRelay.fetch(
            familyId: familyId,
            address: address,
            in: context
        ) ?? CloudNIP29GroupRelay.create(
            familyId: familyId,
            accountPubkey: accountPubkey,
            address: address,
            sourceRelayURL: oldRelayURL,
            isFork: asFork,
            in: context
        )

        relay.isArchived = false
        relay.isFork = relay.isFork || asFork
        relay.updatedAt_ = .now
        activeRelayURL_ = address.relayURL
        updatedAt_ = .now
        persistedState = .active
        return relay
    }

    /// Selects an existing relay branch. No history or fork record is removed.
    @discardableResult
    func switchActiveRelay(to relayURL: String, in context: NSManagedObjectContext) -> Bool {
        guard let groupId = groupId_ else { return false }
        let address = NIP29GroupAddress(relayURL: relayURL, groupId: groupId)
        guard let relay = CloudNIP29GroupRelay.fetch(
            familyId: familyId,
            address: address,
            in: context
        ), !relay.isArchived else { return false }

        activeRelayURL_ = address.relayURL
        updatedAt_ = .now
        relay.lastVisitedAt_ = .now
        return true
    }

    func relayBranches(in context: NSManagedObjectContext) -> [CloudNIP29GroupRelay] {
        CloudNIP29GroupRelay.fetchAll(familyId: familyId, in: context)
    }
}

extension CloudNIP29Group: Identifiable {}
