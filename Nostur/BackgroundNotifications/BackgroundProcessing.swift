//
//  BackgroundProcessing.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/12/2023.
//

import Foundation
import BackgroundTasks

func scheduleDatabaseCleaningIfNeeded() {
#if DEBUG
    L.maintenance.debug("scheduleDatabaseCleaningIfNeeded()")
#endif
    let lastMaintenanceTimestamp = Date(timeIntervalSince1970: TimeInterval(SettingsStore.shared.lastMaintenanceTimestamp))

    // don't do maintenance more than once every 3 days
    let hoursAgo = Date(timeIntervalSinceNow: -259200)
    guard lastMaintenanceTimestamp < hoursAgo else {
#if DEBUG
        L.maintenance.debug("Skipping maintenance");
#endif
        return
    }
#if DEBUG
    L.maintenance.debug("Scheduling time based maintenance")
#endif

    
    let request =  BGProcessingTaskRequest(identifier: "com.nostur.db-cleanup")
    request.requiresExternalPower = true
    request.requiresNetworkConnectivity = false
    do {
        try BGTaskScheduler.shared.submit(request)
#if DEBUG
        L.maintenance.debug("BGTaskScheduler.shared.submit")
#endif
    } catch {
#if DEBUG
        L.maintenance.debug("Could not schedule database cleaning: \(error)")
#endif
    }
}
