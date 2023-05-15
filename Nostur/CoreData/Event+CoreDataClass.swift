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
    
    var likesDidChange = PassthroughSubject<Int64, Never>()
    var zapsDidChange = PassthroughSubject<(Int64, Int64), Never>()
    var postDeleted = PassthroughSubject<String, Never>()
    var repliesUpdated = PassthroughSubject<[Event], Never>()
    var replyToUpdated = PassthroughSubject<Event, Never>()
    var replyToRootUpdated = PassthroughSubject<Event, Never>()
    var firstQuoteUpdated = PassthroughSubject<Event, Never>()
    var contactUpdated = PassthroughSubject<Contact, Never>()
    var contactsUpdated = PassthroughSubject<[Contact], Never>()
    
//    private var eventsQueue = DispatchQueue(label: "com.nostur.events")
    
    var parentEvents: [Event] = []
    
//    var parentEvents: [Event] {
//        get {
//            return eventsQueue.sync {
//                _parentEvents
//            }
//        }
//        set {
//            eventsQueue.async(flags: .barrier) {
//                self._parentEvents = newValue
//            }
//        }
//    }
 
    var isPreview:Bool = false
    var previewImages:[UIImage] = []
}

