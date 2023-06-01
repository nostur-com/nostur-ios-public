//
//  PersistentNotification+CoreDataClass.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/06/2023.
//
//

import Foundation
import CoreData

@objc(PersistentNotification)
public class PersistentNotification: NSManagedObject {

    public enum PersistentNotificationType:String {
        case none = "NONE"
        case newFollowers = "NEW_FOLLOWERS"
    }
}
