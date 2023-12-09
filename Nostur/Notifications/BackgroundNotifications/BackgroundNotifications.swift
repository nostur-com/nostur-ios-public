//
//  BackgroundNotifications.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/12/2023.
//

import SwiftUI
import BackgroundTasks

// Schedule a background fetch task
func scheduleAppRefresh() {
    L.og.debug("scheduleAppRefresh()")
    let request = BGAppRefreshTaskRequest(identifier: "com.nostur.app-refresh")
    request.earliestBeginDate = .now.addingTimeInterval(60) // 60 seconds. Should maybe be longer for battery life, 5-30 minutes? Need to test
    try? BGTaskScheduler.shared.submit(request)
}

// The background fetch task will run this to check for new notifications
func checkForNotifications() {
    bg().perform {
        guard let account = account() else { return }
        let lastSeenPostCreatedAt = account.lastSeenPostCreatedAt
        let accountPubkey = account.publicKey

        ConnectionPool.shared.connectAll()
        
        let reqTask = ReqTask(
            subscriptionId: "BG",
            reqCommand: { taskId in
                L.og.debug("checkForNotifications.reqCommand")
                let since = NTimestamp(timestamp: Int(lastSeenPostCreatedAt))
                bg().perform {
                    NotificationsViewModel.shared.needsUpdate = true
                    
                    DispatchQueue.main.async {
                        // Mentions kinds (1,9802,30023) and DM (4)
                        req(RM.getMentions(pubkeys: [accountPubkey], kinds:[1,4,9802,30023], subscriptionId: "Notifications-BG", since: since))
                    }
                }
            },
            processResponseCommand: { taskId, relayMessage, event in
                L.og.debug("checkForNotifications.processResponseCommand")
                bg().perform {
                    NotificationsViewModel.shared.checkForUnreadMentions()
                }
            },
            timeoutCommand: { taskId in
                L.og.debug("checkForNotifications.timeoutCommand")
            }
        )
        Backlog.shared.add(reqTask)
        reqTask.fetch()
    }
}
