//
//  BackgroundProcessing.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/12/2023.
//

import Foundation
import BackgroundTasks

func scheduleDatabaseCleaningIfNeeded() {
    L.maintenance.debug("scheduleDatabaseCleaningIfNeeded()")
    let lastMaintenanceTimestamp = Date(timeIntervalSince1970: TimeInterval(SettingsStore.shared.lastMaintenanceTimestamp))

    // don't do maintenance more than once every 3 days
    let hoursAgo = Date(timeIntervalSinceNow: (-3 * 24 * 60 * 60))
    guard lastMaintenanceTimestamp < hoursAgo else {
        L.maintenance.debug("Skipping maintenance");
        return
    }
    L.maintenance.debug("Scheduling time based maintenance")

    
    let request =  BGProcessingTaskRequest(identifier: "com.nostur.db-cleanup")
    request.requiresExternalPower = true
    request.requiresNetworkConnectivity = false
    do {
        try BGTaskScheduler.shared.submit(request)
        L.maintenance.debug("BGTaskScheduler.shared.submit")
    } catch {
        L.maintenance.debug("Could not schedule database cleaning: \(error)")
    }
}

import CoreData

class DatabaseCleanUpOperation: Operation {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    override func main() {
        context.performAndWait {
            do {
                Maintenance.databaseCleanUp(context)
                try context.save() // backgroundContext (saves to main)
                DataProvider.shared().save() { // main context (saves to disk)
                    Task {
                        await Importer.shared.preloadExistingIdsCache()
                    }
                }
            } catch {
                L.maintenance.error("Error running daily maintenance: \(error)")
            }
        }
    }
}
