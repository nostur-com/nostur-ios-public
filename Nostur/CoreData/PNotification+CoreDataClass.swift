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
    
    static func create(pubkey:String, followers:[String], context:NSManagedObjectContext) -> PersistentNotification {
        let newFollowersNotification = PersistentNotification(context: context)
        newFollowersNotification.id = UUID()
        newFollowersNotification.createdAt = .now
        newFollowersNotification.pubkey = pubkey
        newFollowersNotification.type = .newFollowers
        newFollowersNotification.content = followers.joined(separator: ",")
        return newFollowersNotification
    }
}
