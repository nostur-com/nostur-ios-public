//
//  Event+Notifications.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/03/2023.
//

import Foundation
import CoreData

extension Event {
    // ON ROOT DM, TO TRACK UNREAD PER CONVERSATION
    // HERE AND NOT ON ACCOUNT BECAUSE NEED TO TRACK PER CONVERSATION
    @NSManaged public var lastSeenDMCreatedAt:Int64
}
