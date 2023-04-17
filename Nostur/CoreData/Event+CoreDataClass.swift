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

public class Event: NSManagedObject, Identifiable {
    
    private var eventsQueue = DispatchQueue(label: "com.nostur.events")
    
    private var _parentEvents: [Event] = []
    
    var parentEvents: [Event] {
        get {
            return eventsQueue.sync {
                _parentEvents
            }
        }
        set {
            eventsQueue.async(flags: .barrier) {
                self._parentEvents = newValue
            }
        }
    }
    
    var previewImages:[UIImage] = []
}

