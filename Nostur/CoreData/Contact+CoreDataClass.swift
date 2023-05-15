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
}
