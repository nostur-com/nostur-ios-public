//
//  ListState+CoreDataClass.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/03/2023.
//
//

import Foundation
import CoreData

@objc(ListState)
public class ListState: NSManagedObject {

    static func fetchListStates(context:NSManagedObjectContext) -> [ListState] {
        let request = NSFetchRequest<ListState>(entityName: "ListState")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ListState.updatedAt, ascending: false)]
        return (try? context.fetch(request)) ?? []
    }
}
