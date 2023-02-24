//
//  Notifications.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/02/2023.
//

import Foundation

func sendNotification(_ name:Notification.Name, _ object: Any? = nil) {
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
    
    static var addedNotes: Notification.Name {
        return Notification.Name("addedNotes")
    }
    
    static var shouldScrollToNote: Notification.Name {
        return Notification.Name("shouldScrollToNote")
    }
    
    static var shouldScrollToUnreadNote: Notification.Name {
        return Notification.Name("shouldScrollToUnreadNote")
    }
    
    
    static var newNotesAvailable: Notification.Name {
        return Notification.Name("newNotesAvailable")
    }
    
    static var wantsNewEvents: Notification.Name {
        return Notification.Name("wantsNewEvents")
    }
    
    static var requestEventReferences: Notification.Name {
        return Notification.Name("requestEventReferences")
    }
    
    static var requestForJustAppeared: Notification.Name {
        return Notification.Name("requestForJustAppeared ")
    }
}
