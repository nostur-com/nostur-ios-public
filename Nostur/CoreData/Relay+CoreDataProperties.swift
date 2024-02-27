//
//  Relay+CoreDataClass.swift
//  Nostur
//
//  Created by Fabian Lachman on 18/01/2023.
//
//

import Foundation
import CoreData

extension Relay {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Relay> {
        let fr = NSFetchRequest<Relay>(entityName: "Relay")
        fr.sortDescriptors = []
        return fr
    }

    @NSManaged public var createdAt: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var read: Bool
    @NSManaged public var url: String?
    @NSManaged public var write: Bool

    @NSManaged public var lists: NSSet?
    
    var lists_:[NosturList] {
        get { (lists?.allObjects as? [NosturList]) ?? [] }
        set { lists = NSSet(array: newValue) }
    }
    
    @NSManaged public var excludedPubkeys_: String?
    
    var excludedPubkeys:Set<String> {
        get {
            guard let pubkeysString = excludedPubkeys_ else { return [] }
            return Set(pubkeysString.split(separator: " ", omittingEmptySubsequences: true).map { String($0) })
        }
        set { 
            excludedPubkeys_ = newValue.joined(separator: " ")
        }
    }
    
    public func toStruct() -> RelayData {
        return RelayData.new(url: (url ?? ""), read: read, write: write, search: false, auth: false, excludedPubkeys: excludedPubkeys)
    }
}

// MARK: Generated accessors for contacts
extension Relay {

    @objc(addListsObject:)
    @NSManaged public func addToLists(_ value: NosturList)

    @objc(removeListsObject:)
    @NSManaged public func removeFromLists(_ value: NosturList)

    @objc(addLists:)
    @NSManaged public func addToLists(_ values: NSSet)

    @objc(removeLists:)
    @NSManaged public func removeFromLists(_ values: NSSet)

}

extension Relay : Identifiable {
    
    static func fetchAll(context: NSManagedObjectContext) -> [Relay] {
        let fr = Relay.fetchRequest()
        return (try? context.fetch(fr)) ?? []
    }
}
