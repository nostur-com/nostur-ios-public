//
//  CloudRelay+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/11/2023.
//
//

import Foundation
import CoreData


extension CloudRelay {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CloudRelay> {
        return NSFetchRequest<CloudRelay>(entityName: "CloudRelay")
    }

    @NSManaged public var createdAt_: Date?
    @NSManaged public var updatedAt_: Date?
    @NSManaged public var excludedPubkeys_: String?
    @NSManaged public var read: Bool
    @NSManaged public var write: Bool
    @NSManaged public var search: Bool
    @NSManaged public var url_: String?
    
    public var createdAt:Date {
        get {
            createdAt_ ?? .distantPast
        }
        set {
            createdAt_ = newValue
        }
    }
    
    public var updatedAt:Date {
        get {
            updatedAt_ ?? .distantPast
        }
        set {
            updatedAt_ = newValue
        }
    }
    
    public var excludedPubkeys:Set<String> {
        get {
            guard let pubkeysString = excludedPubkeys_ else { return [] }
            return Set(pubkeysString.split(separator: " ", omittingEmptySubsequences: true).map { String($0) })
        }
        set {
            updatedAt_ = .now
            excludedPubkeys_ = newValue.joined(separator: " ")
        }
    }
    
    public func toStruct() -> RelayData {
        return RelayData.new(url: (url_ ?? ""),
                      read: read,
                      write: write,
                      search: search,

                      excludedPubkeys: excludedPubkeys)
    }

}

extension CloudRelay : Identifiable {
    static func fetchAll(context: NSManagedObjectContext = context()) -> [CloudRelay] {
        let fr = CloudRelay.fetchRequest()
        return (try? context.fetch(fr)) ?? []
    }
}


