//
//  PersistentNotification+CoreDataClass.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/06/2023.
//
//

import Foundation
import CoreData

public typealias PNType = PersistentNotification.PersistentNotificationType

@objc(PersistentNotification)
public class PersistentNotification: NSManagedObject {

    public enum PersistentNotificationType:String {
        case none = "NONE"
        case newFollowers = "NEW_FOLLOWERS"
        case failedZap = "FAILED_ZAP"
        case failedZaps = "FAILED_ZAPS" // Error
        case failedZapsTimeout = "FAILED_ZAPS_TIMEOUT" // Timeout
        case failedLightningInvoice = "FAILED_LIGHTNING_INVOICE"
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
    
    static func createFailedNWCZap(pubkey:String, message:String, context:NSManagedObjectContext) -> PersistentNotification {
        let failedZapNotification = PersistentNotification(context: context)
        failedZapNotification.id = UUID()
        failedZapNotification.createdAt = .now
        failedZapNotification.pubkey = pubkey
        failedZapNotification.type = .failedZap
        failedZapNotification.content = message
        return failedZapNotification
    }
    
    static func createFailedLightningInvoice(pubkey:String, message:String, context:NSManagedObjectContext) -> PersistentNotification {
        let failedZapNotification = PersistentNotification(context: context)
        failedZapNotification.id = UUID()
        failedZapNotification.createdAt = .now
        failedZapNotification.pubkey = pubkey
        failedZapNotification.type = .failedLightningInvoice
        failedZapNotification.content = message
        return failedZapNotification
    }
    
    static func createFailedNWCZaps(pubkey:String, message:String, context:NSManagedObjectContext) -> PersistentNotification {
        let failedZapNotification = PersistentNotification(context: context)
        failedZapNotification.id = UUID()
        failedZapNotification.createdAt = .now
        failedZapNotification.pubkey = pubkey
        failedZapNotification.type = .failedZaps
        failedZapNotification.content = message
        return failedZapNotification
    }
    
    static func createTimeoutNWCZaps(pubkey:String, message:String, context:NSManagedObjectContext) -> PersistentNotification {
        let failedZapNotification = PersistentNotification(context: context)
        failedZapNotification.id = UUID()
        failedZapNotification.createdAt = .now
        failedZapNotification.pubkey = pubkey
        failedZapNotification.type = .failedZaps
        failedZapNotification.content = message
        return failedZapNotification
    }
}
