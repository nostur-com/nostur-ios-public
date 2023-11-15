//
//  CloudDMState+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/11/2023.
//
//

import Foundation
import CoreData


extension CloudDMState {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CloudDMState> {
        return NSFetchRequest<CloudDMState>(entityName: "CloudDMState")
    }

    @NSManaged public var accepted: Bool
    @NSManaged public var accountPubkey: String?
    @NSManaged public var contactPubkey: String?
    @NSManaged public var markedReadAt: Date?
    @NSManaged public var isPinned: Bool
    @NSManaged public var isHidden: Bool

}

extension CloudDMState : Identifiable {

}
