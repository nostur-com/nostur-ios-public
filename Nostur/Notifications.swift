//
//  Notifications.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/02/2023.
//

import Foundation

func sendNotification(_ name:Notification.Name, _ object: Any?) {
    NotificationCenter.default.post(Notification(name: name, object: object))
}
func receiveNotification(_ name: Notification.Name) -> NotificationCenter.Publisher {
    return NotificationCenter.default.publisher(for: name)
}

extension Notification.Name {
    static var timelineWillReceiveNewNotes: Notification.Name {
        return Notification.Name("timelineWillReceiveNewNotes")
    }
    
    static var unpublisherTimerNextTick: Notification.Name {
        return Notification.Name("unpublisherTimerNextTick")
    }
    
    static var blockListUpdated: Notification.Name {
        return Notification.Name("blockListUpdated")
    }
    
    static var willDeleteAllEvents: Notification.Name {
        return Notification.Name("willDeleteAllEvents")
    }
    
    static var activeAccountChanged: Notification.Name {
        return Notification.Name("activeAccountChanged")
    }
    
    static var timelinePredicateChanged: Notification.Name {
        return Notification.Name("timelinePredicateChanged")
    }
}
