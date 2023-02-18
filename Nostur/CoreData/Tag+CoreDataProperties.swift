//
//  Tag+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 18/02/2023.
//
//

import Foundation
import CoreData


extension Tag {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Tag> {
        return NSFetchRequest<Tag>(entityName: "Tag")
    }

    @NSManaged public var type: String
    @NSManaged public var index1: String?
    @NSManaged public var index2: String?
    @NSManaged public var index3: String?
    @NSManaged public var index4: String?
    @NSManaged public var event: Event?
    @NSManaged public var contact: Contact?

}

extension Tag : Identifiable {
    
    var npub:String { get { index1 != nil ? try! NIP19(prefix: "npub", hexString: index1!).displayString : "⏤⏤" } }

    
    var contactUsername:String {
        get {
            contact?.username ?? String(npub.prefix(9))
        }
    }
    
    var contactPubkey:String { index1 ??  "⏤⏤" }
}
