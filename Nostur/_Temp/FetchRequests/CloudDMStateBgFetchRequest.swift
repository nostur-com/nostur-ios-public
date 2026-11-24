//
//  DMStateBgFetchRequest.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/01/2024.
//

import Foundation
import CoreData

class CloudDMStateFetchRequest: NSObject, NSFetchedResultsControllerDelegate  {
    
    let frc: NSFetchedResultsController<CloudDMState>
    
    override init() {
        let fr = CloudDMState.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \CloudDMState.lastMessageTimestamp_, ascending: false)]
        self.frc = NSFetchedResultsController(fetchRequest: fr, managedObjectContext: viewContext(), sectionNameKeyPath: nil, cacheName: nil)
        super.init()
        frc.delegate = self
        do {
            try self.frc.performFetch()
            guard let items = self.frc.fetchedObjects else { return }
#if DEBUG
            L.og.debug("CloudDMStateFetchRequest CloudDMState: \(items.count) -[LOG]-")
#endif
            onChange(items)
        }
        catch {
            L.og.error("🔴🔴🔴 CloudDMStateFetchRequest failed to fetch items \(error.localizedDescription)")
        }
        
    }
    
    func onChange(_ dmStates: [CloudDMState]) {
        removeDuplicateDMStates(dmStates: dmStates)
        DMsVM.shared.dmStates = dmStates.filter { $0.accountPubkey_ == DMsVM.shared.accountPubkey }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        guard let dmStates = controller.fetchedObjects as? [CloudDMState] else { return }
        self.onChange(dmStates)
    }
    
    private func removeDuplicateDMStates(dmStates: [CloudDMState]) {
        var uniqueDMStates = Set<String>()
        let sortedDMStates = dmStates
            .sorted {
                (max($0.markedReadAt_ ?? .distantPast, $0.lastMessageTimestamp_ ?? .distantPast)) > (max($1.markedReadAt_ ?? .distantPast, $1.lastMessageTimestamp_ ?? .distantPast))
            }
            .sorted {
                $0.participantPubkeys_ != nil && $1.participantPubkeys_ == nil
            }
            .sorted {
                $0.accountPubkey_ != nil && $1.accountPubkey_ == nil
            }

        let toDelete = sortedDMStates
            .filter { dmState in
                guard let accountPubkey = dmState.accountPubkey_ else { return true }
                return !uniqueDMStates.insert(accountPubkey + "-" + dmState.conversationId).inserted
            }
        // A newer message timestamp does not imply newer read progress. Preserve
        // each duplicate's read cursor before deleting it.
        for duplicate in toDelete {
            guard let survivor = sortedDMStates.first(where: {
                $0.accountPubkey_ == duplicate.accountPubkey_ &&
                $0.conversationId == duplicate.conversationId
            }), survivor !== duplicate,
                  let readAt = duplicate.markedReadAt_,
                  readAt > (survivor.markedReadAt_ ?? .distantPast) else { continue }
            survivor.markedReadAt_ = readAt
        }
#if DEBUG
        L.cloud.debug("CloudDMStateFetchRequest: deleted \(toDelete.count) DM conversation states")
#endif
        toDelete.forEach({ dmState in
            viewContext().delete(dmState)
        })
        if !toDelete.isEmpty {
            DataProvider.shared().saveToDiskNow(.viewContext)
        }
    }
}
