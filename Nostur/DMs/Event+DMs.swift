//
//  Event+DMs.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/03/2023.
//

import Foundation
import CoreData

extension Event {
        
    // ON ROOT DM TO KEEP TRACK IF DM REQUEST IS ACCEPTED
    // HERE AND NOT ON CONTACT BECAUSE NEED TO TRACK PER ACCOUNT-CONTACT PAIR (EVENT.PUBKEY-EVENT.P on ROOT DM)
    // TODO: REMOVE FROM CONTACT
    @NSManaged public var dmAccepted:Bool
}
