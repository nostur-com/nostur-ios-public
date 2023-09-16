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

extension Contact {
    func bgContact() -> Contact? {
        if Thread.isMainThread {
            L.og.info("🔴🔴🔴 toBG() should be in bg already, switching now but should fix code")
            return DataProvider.shared().bg.performAndWait {
                return DataProvider.shared().bg.object(with: self.objectID) as? Contact
            }
        }
        else {
            return DataProvider.shared().bg.object(with: self.objectID) as? Contact
        }
    }
}
