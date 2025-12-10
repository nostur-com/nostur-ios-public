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
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \CloudDMState.markedReadAt_, ascending: false)]
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
        DirectMessageViewModel.default.dmStates = dmStates
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

        let duplicates = sortedDMStates
            .filter { dmState in
                guard let accountPubkey = dmState.accountPubkey_ else { return false }
                return !uniqueDMStates.insert(accountPubkey + "-" + dmState.conversationId).inserted
            }
#if DEBUG
        L.cloud.debug("CloudDMStateFetchRequest: \(duplicates.count) duplicate DM conversation states")
#endif
        duplicates.forEach({ duplicateDMState in
            viewContext().delete(duplicateDMState)
        })
        if !duplicates.isEmpty {
            DataProvider.shared().saveToDiskNow(.viewContext)
        }
    }
}
