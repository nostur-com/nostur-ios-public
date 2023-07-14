//
//  Account+Notifications.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/03/2023.
//

import Foundation
import CoreData

extension Account {
    @NSManaged public var lastSeenPostCreatedAt:Int64
    @NSManaged public var lastSeenReactionCreatedAt:Int64
    @NSManaged public var lastSeenZapCreatedAt:Int64
    @NSManaged public var lastSeenDMRequestCreatedAt:Int64
    @NSManaged public var lastFollowerCreatedAt:Int64
}

