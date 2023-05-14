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

