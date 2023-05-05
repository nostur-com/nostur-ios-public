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
    
    static var muteListUpdated: Notification.Name {
        return Notification.Name("muteListUpdated")
    }
    
    static var willDeleteAllEvents: Notification.Name {
        return Notification.Name("willDeleteAllEvents")
    }
    
    static var didDeleteAllEvents: Notification.Name {
        return Notification.Name("didDeleteAllEvents")
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
    
    static var shouldScrollToRecent: Notification.Name {
        return Notification.Name("shouldScrollToRecent")
    }
        
    static var scrollABit: Notification.Name {
        return Notification.Name("scrollABit")
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
        return Notification.Name("requestForJustAppeared")
    }
    
    static var badgeAwardFetched: Notification.Name {
        return Notification.Name("badgeAwardFetched")
    }
    
    static var badgeDefinitionFetched: Notification.Name {
        return Notification.Name("badgeDefinitionFetched")
    }
    
    static var profileBadgesFetched: Notification.Name {
        return Notification.Name("profileBadgesFetched")
    }
    static var editingPrivateNote: Notification.Name {
        return Notification.Name("editingPrivateNote")
    }
    static var newPrivateNoteOnPost: Notification.Name {
        return Notification.Name("newPrivateNoteOnPost")
    }
    static var newPrivateNoteOnContact: Notification.Name {
        return Notification.Name("newPrivateNoteOnContact")
    }
    
    static var viewNeedsUpdate: Notification.Name {
        return Notification.Name("viewNeedsUpdate")
    }
    
    static var updateUnreadCount: Notification.Name {
        return Notification.Name("updateUnreadCount")
    }
    
    static var endOnboarding: Notification.Name {
        return Notification.Name("endOnboarding")
    }
    
    static var updateNotificationsCount: Notification.Name {
        return Notification.Name("updateNotificationsCount")
    }
    
    static var updateDMsCount: Notification.Name {
        return Notification.Name("updateDMsCount")
    }
    
    static var newPostsForView: Notification.Name {
        return Notification.Name("newPostsForView")
    }
    
    static var listStatus: Notification.Name {
        return Notification.Name("listStatus")
    }
    
    static var fullScreenView: Notification.Name {
        return Notification.Name("fullScreenView")
    }
    
    static var newFollowingListFromRelay: Notification.Name {
        return Notification.Name("newFollowingListFromRelay")
    }
    
    static var requestConfirmationChangedFollows: Notification.Name {
        return Notification.Name("requestConfirmationChangedFollows")
    }
    
    static var reportPost: Notification.Name {
        return Notification.Name("reportPost")
    }
    
    static var reportContact: Notification.Name {
        return Notification.Name("reportContact")
    }
    
    static var requestDeletePost: Notification.Name {
        return Notification.Name("requestDeletePost")
    }
    
    static var navigateTo: Notification.Name {
        return Notification.Name("navigateTo")
    }
    
    static var clearNavigation: Notification.Name {
        return Notification.Name("clearNavigation")
    }
    
    static var navigateToOnMain: Notification.Name {
        return Notification.Name("navigateToOnMain")
    }
     
    static var newPostSaved: Notification.Name {
        return Notification.Name("newPostSaved")
    }
    
    static var createNewReply: Notification.Name {
        return Notification.Name("createNewReply")
    }
    static var createNewQuoteOrRepost: Notification.Name {
        return Notification.Name("createNewQuoteOrRepost")
    }
    
    static var followersChanged: Notification.Name {
        return Notification.Name("followersChanged")
    }
    
    static var explorePubkeysChanged: Notification.Name {
        return Notification.Name("explorePubkeysChanged")
    }
        
    static var listPubkeysChanged: Notification.Name {
        return Notification.Name("listPubkeysChanged")
    }
    
    static var onBoardingIsShownChanged: Notification.Name {
        return Notification.Name("onBoardingIsShownChanged")
    }
    
    static var mutedWordsChanged: Notification.Name {
        return Notification.Name("mutedWordsChanged")
    }
    
    static var socketNotification: Notification.Name {
        return Notification.Name("socketNotification")
    }
    
    static var anyStatus: Notification.Name {
        return Notification.Name("anyStatus")
    }
    
    static var showZapSheet: Notification.Name {
        return Notification.Name("showZapSheet")
    }
    
    static var startPlayingVideo: Notification.Name {
        return Notification.Name("startPlayingVideo")
    }

    static var hideSideBar: Notification.Name {
        return Notification.Name("hideSideBar")
    }
    
    static var showSideBar: Notification.Name {
        return Notification.Name("showSideBar")
    }
    
    static var addRemoveToListsheet: Notification.Name {
        return Notification.Name("addRemoveToListsheet")
    }
    
    static var newEventsInDatabase: Notification.Name {
        return Notification.Name("newEventsInDatabase")
    }
    
    static var newHighlight: Notification.Name {
        return Notification.Name("newHighlight")
    }
    
    static var relayFetchResult: Notification.Name {
        return Notification.Name("relayFetchResult")
    }
    
    static var importedMessagesFromSubscriptionIds: Notification.Name {
        return Notification.Name("importedMessagesFromSubscriptionIds")
    }
    
    static var newMentions: Notification.Name {
        return Notification.Name("newMentions")
    }
    
    static var newReactions: Notification.Name {
        return Notification.Name("newReactions")
    }
    
    static var newZaps: Notification.Name {
        return Notification.Name("newZaps")
    }
}
