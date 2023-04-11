//
//  List+CoreDataClass.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/01/2023.
//
//

import Foundation
import CoreData


public class NosturList: NSManagedObject {

    static func generateExamples(context: NSManagedObjectContext) {
        let contacts = PreviewFetcher.allContacts(context: context)
        for i in 0..<3 {
            let list = NosturList(context: context)
            list.name = "List \(i)"
            list.addToContacts(NSSet(array: contacts.randomSample(count: 10)))
        }
    }
}
