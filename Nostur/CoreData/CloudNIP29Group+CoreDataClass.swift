//
//  CloudNIP29Group+CoreDataClass.swift
//  Nostur
//

import CoreData
import Foundation

@objc(CloudNIP29Group)
public final class CloudNIP29Group: NSManagedObject {}

enum NIP29PersistedGroupState: Int16 {
    case active = 0
    case left = 1
    case archived = 2
}
