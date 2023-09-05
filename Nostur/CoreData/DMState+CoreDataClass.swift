//
//  DMState+CoreDataClass.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/09/2023.
//
//

import Foundation
import CoreData
import Combine

@objc(DMState)
public class DMState: NSManagedObject {
    var didUpdate = PassthroughSubject<Void, Never>()
}
