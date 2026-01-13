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
    
    var zapState: ZapState?
    var parentEvents: [Event] = []
    
    var previewImages: [PostedImageMeta] = []
    var previewVideos: [PostedVideoMeta] = []
    var cancellationId: UUID?
    
    lazy var fastTags: [FastTag] = {
        guard let tagsSerialized = tagsSerialized else { return [] }
        guard let jsonData = tagsSerialized.data(using: .utf8) else { return [] }
        
        guard let jsonArray = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String]] else {
            return []
        }
        
        return jsonArray
            .map { ($0[safe: 0] ?? "WTF", $0[safe: 1] ?? "WTF", $0[safe: 2], $0[safe: 3], $0[safe: 4], $0[safe: 4], $0[safe: 5], $0[safe: 6], $0[safe: 7], $0[safe: 8]) }
    }()
    
    
    lazy var fastPs: [FastTag] = {
        fastTags.filter { $0.0 == "p" && $0.1.count == 64 }
    }()
    
    lazy var fastQs: [FastTag] = {
        fastTags.filter { $0.0 == "q" } // can also be id but also aTag
    }()
}

