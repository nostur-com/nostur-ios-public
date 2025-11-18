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
            .debounce(for: .seconds(0.2), scheduler: RunLoop.main)
            .sink { [unowned self] in
                self._saveRelations()
            }
            .store(in: &subscriptions)
    }
    
    public func addTask(_ task: @escaping SaveRelationTask) {
        self.taskQueue.append(task)
        self.saveRelations()
    }
    
    private func saveRelations() {
        self.saveRelationsSubject.send()
    }
    
    private func _saveRelations() {
        // Always defer to next run loop to avoid nested perform calls
        DispatchQueue.main.async { [weak self] in
            self?.bgContext.perform { [weak self] in
                self?._executeTasksDirectly()
            }
        }
    }
    
    private func _executeTasksDirectly() {
        guard !self.taskQueue.isEmpty else { return }
        
        let tasksToProcess = self.taskQueue
        self.taskQueue.removeAll()
        
#if DEBUG
        L.og.debug("💾💾 Processing \(tasksToProcess.count) relations -[LOG]-")
#endif
        
        for (index, task) in tasksToProcess.enumerated() {
            task()
        }
        
        DataProvider.shared().saveToDiskNow(.bgContext)
    }
    
}
