//
//  RelaysBgFetchRequest.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/01/2024.
//

import Foundation
import CoreData
import NostrEssentials

class CloudRelayBgFetchRequest: NSObject, NSFetchedResultsControllerDelegate  {
    
    let frc: NSFetchedResultsController<CloudRelay>
    
    override init() {
        let fr = CloudRelay.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \CloudRelay.updatedAt_, ascending: false)]
        self.frc = NSFetchedResultsController(fetchRequest: fr, managedObjectContext: bg(), sectionNameKeyPath: nil, cacheName: nil) 
        super.init()
        frc.delegate = self
        bg().perform { [weak self] in
            do {
                try self?.frc.performFetch()
                guard let items = self?.frc.fetchedObjects else { return }
#if DEBUG
                L.og.debug("BGAccountFetchRequest CloudRelay: \(items.count) -[LOG]-")
#endif
                self?.onChange(items)
            }
            catch {
                L.og.error("🔴🔴🔴 BGAccountFetchRequest failed to fetch items \(error.localizedDescription)")
            }
        }
    }
    
    func onChange(_ relays: [CloudRelay]) {
        removeDuplicateRelays(relays: relays)
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        guard let relays = controller.fetchedObjects as? [CloudRelay] else { return }
        onChange(relays)
    }
    
    private func removeDuplicateRelays(relays: [CloudRelay]) {
        var uniqueRelays = Set<String>()
        let sortedRelays = relays.sorted { $0.updatedAt > $1.updatedAt }

        let duplicates = sortedRelays
            .filter { relay in
                guard let url = relay.url_ else { return false }
                let normalizedUrl = normalizeRelayUrl(url)
                return !uniqueRelays.insert(normalizedUrl).inserted
            }

        if duplicates.count > 0 {
#if DEBUG
            L.cloud.debug("BGAccountFetchRequest Deleting: \(duplicates.count) duplicate relays")
#endif
        }
        duplicates.forEach({ duplicateRelay in
            bg().delete(duplicateRelay)
        })
        if !duplicates.isEmpty {
            DataProvider.shared().saveToDiskNow(.bgContext)
        }
    }
}
