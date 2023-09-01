//
//  Contact+CoreDataClass.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/01/2023.
//
//

import Foundation
import CoreData
import Combine

public class Contact: NSManagedObject {
    var contactUpdated = PassthroughSubject<Contact, Never>()
    var nip05updated = PassthroughSubject<(Bool, String, String), Never>()
    
    var zapStateChanged = PassthroughSubject<(ZapState?, ZapEtag?), Never>()
        
    public enum ZapState:String {
        case initiated = "INITIATED"
        case nwcConfirmed = "NWC_CONFIRMED"
        case zapReceiptConfirmed = "ZAP_RECEIPT_CONFIRMED"
        case failed = "FAILED"
        case cancelled = "CANCELLED" // (by Undo)
    }
    
    var zapState:ZapState?
}

public typealias ZapEtag = String
