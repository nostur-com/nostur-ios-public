//
//  BGFetchRequest.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/01/2024.
//

import Foundation
import CoreData

// Trying to do get @FetchRequest realtime live updates, including iCloud sync. But in background.
class BookmarkBgFetchRequest: NSObject, NSFetchedResultsControllerDelegate  {
    
    let frc: NSFetchedResultsController<Bookmark>
    
    override init() {
        let fr = Bookmark.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Bookmark.createdAt, ascending: false)]
        self.frc = NSFetchedResultsController(fetchRequest: fr, managedObjectContext: bg(), sectionNameKeyPath: nil, cacheName: nil)
        super.init()
        frc.delegate = self
        bg().perform { [weak self] in
            do {
                try self?.frc.performFetch()
                guard let items = self?.frc.fetchedObjects else { return }
#if DEBUG
                L.og.debug("BookmarkBgFetchRequest items \(items.count) -[LOG]-")
#endif
                self?.onChange(items)
            }
            catch {
                L.og.error("🔴🔴🔴 BookmarkBgFetchRequest failed to fetch items \(error.localizedDescription) -[LOG]-")
            }
        }
        
    }
    
    func onChange(_ bookmarks: [Bookmark]) { }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        guard let items = controller.fetchedObjects as? [Bookmark] else { return }
        onChange(items)
    }
}




