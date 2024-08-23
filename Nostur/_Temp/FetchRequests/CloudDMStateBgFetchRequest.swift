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
        self.frc = NSFetchedResultsController(fetchRequest: fr, managedObjectContext: viewContext(), sectionNameKeyPath: nil, cacheName: nil) // TODO: Try cache?
        super.init()
        frc.delegate = self
        do {
            try self.frc.performFetch()
            guard let items = self.frc.fetchedObjects else { return }
            L.og.debug("CloudDMStateFetchRequest CloudDMState: \(items.count) -[LOG]-")
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
        let sortedDMStates = dmStates.sorted { ($0.markedReadAt_ ?? .distantPast) > ($1.markedReadAt_ ?? .distantPast) }

        let duplicates = sortedDMStates
            .filter { dmState in
                guard dmState.contactPubkey_ != nil else { return false }
                guard dmState.accountPubkey_ != nil else { return false }
                return !uniqueDMStates.insert(dmState.conversionId).inserted
            }

        L.cloud.debug("CloudDMStateFetchRequest: \(duplicates.count) duplicate DM conversation states")
        duplicates.forEach({ duplicateDMState in
            viewContext().delete(duplicateDMState)
        })
        if !duplicates.isEmpty {
            viewContextSave()
        }
    }
}
