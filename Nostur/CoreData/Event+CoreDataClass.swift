//
//  Event+CoreDataClass.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/01/2023.
//
//

import Foundation
import CoreData
import UIKit
import Combine

public class Event: NSManagedObject, Identifiable {
    
    var repostsDidChange = PassthroughSubject<Int64, Never>()
    var likesDidChange = PassthroughSubject<Int64, Never>()
    var zapsDidChange = PassthroughSubject<(Int64, Int64), Never>()
    var postDeleted = PassthroughSubject<String, Never>()
    var repliesUpdated = PassthroughSubject<[Event], Never>()
    var replyToUpdated = PassthroughSubject<Event, Never>()
    var replyToRootUpdated = PassthroughSubject<Event, Never>()
    var firstQuoteUpdated = PassthroughSubject<Event, Never>()
    var contactUpdated = PassthroughSubject<Contact, Never>()
    var contactsUpdated = PassthroughSubject<[Contact], Never>()
    var relaysUpdated = PassthroughSubject<String, Never>()
    var zapStateChanged = PassthroughSubject<ZapState?, Never>()
    var updateNRPost = PassthroughSubject<Event, Never>()
        
    enum ZapState:String {
        case initiated = "INITIATED"
        case nwcConfirmed = "NWC_CONFIRMED"
        case zapReceiptConfirmed = "ZAP_RECEIPT_CONFIRMED"
        case failed = "FAILED"
        case cancelled = "CANCELLED" // (by Undo)
    }
    
    var zapState:ZapState? {
        didSet {
            zapStateChanged.send(zapState)
        }
    }
    var parentEvents: [Event] = []
    
    var isPreview:Bool = false
    var previewImages:[UIImage] = []
    var cancellationId:UUID?
    
    public override func validateValue(_ value: AutoreleasingUnsafeMutablePointer<AnyObject?>, forKey key: String) throws {
        
        // Daily maintenance deletes old events, but these events don't have proper inverse relationship (not needed)
        // But core data seems to cry about it, and crashes when it tries to access a relation that has been deleted
        // Ignoring validation seems to fix it, hopefully it doesn't break other things...
        let skipValidationFor = ["replyTo","reactionTo", "replyToRoot", "firstQuote", "zapFromRequest", "zappedEvent"]
        if skipValidationFor.contains(key) {
            // Ignore validation for the relationship
            return
        }
        
        try super.validateValue(value, forKey: key)
    }
}

