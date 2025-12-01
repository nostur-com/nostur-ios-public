//
//  ProfileUpdateHandler.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/11/2025.
//

import Foundation
import CoreData

func handleProfileUpdate(nEvent: NEvent, savedEvent: Event, context: NSManagedObjectContext) {
    guard nEvent.kind == .setMetadata else { return }
    Contact.saveOrUpdateContact(event: nEvent, context: context)
}
