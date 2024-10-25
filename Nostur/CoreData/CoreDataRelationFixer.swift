//
//  CoreDataRelationFixer.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/10/2024.
//

import Foundation
import CoreData
import Combine

typealias SaveRelationTask = () -> Void

// Helper for weird crash because Core Data cannot save object not saved if it has a relation to a saved object.
// Both objects need to be either saved or not saved, it seems.
class CoreDataRelationFixer {
    
    static let shared = CoreDataRelationFixer()
    
    private var taskQueue: [SaveRelationTask] = []
    private var bgContext: NSManagedObjectContext = bg()
    private var saveRelationsSubject = PassthroughSubject<Void, Never>()
    private var subscriptions = Set<AnyCancellable>()
    
    private init() {
        saveRelationsSubject
            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { [unowned self] in
                self._saveRelations()
            }
            .store(in: &subscriptions)
    }
    
    public func addTask(_ task: @escaping SaveRelationTask) {
        self.taskQueue.append(task)
    }
    
    public func saveRelations() {
        self.saveRelationsSubject.send()
    }
    
    private func _saveRelations() {
        bgContext.perform {
            guard !self.taskQueue.isEmpty else { return }
            L.og.debug("💾💾 Saving \(self.taskQueue.count) relations")
            for task in self.taskQueue {
                task()
            }
            
            // Optionally clear the queue after executing tasks
            self.taskQueue.removeAll()
            
            do {
                try self.bgContext.save()
            }
            catch {
                L.og.error("🔴🔴 Could not save bgContext \(error)")
            }
        }
    }
    
}
