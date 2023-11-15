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
        return RelayData(read: read, url: (url ?? ""), write: write, excludedPubkeys: excludedPubkeys)
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


// Struct to pass around and avoid all the multi threading NSManagedContext problems
public struct RelayData: Identifiable, Hashable, Equatable {
    public var id: String { url.lowercased() }
    public var read: Bool
    public var url: String
    public var write: Bool
    public var excludedPubkeys:Set<String>
    
    mutating func setRead(_ value:Bool) {
        self.read = value
    }
    
    mutating func setWrite(_ value:Bool) {
        self.write = value
    }
    
    mutating func setExcludedPubkeys(_ value:Set<String>) {
        self.excludedPubkeys = value
    }
}
