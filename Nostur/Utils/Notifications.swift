//
//  Notifications.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/02/2023.
//

import Foundation

func sendNotification(_ name: Notification.Name, _ object: Any? = nil) {
//    #if DEBUG
//    L.og.info("🗡️🗡️ sendNotification: \(name.rawValue)")
//    #endif
    NotificationCenter.default.post(Notification(name: name, object: object))
}
func receiveNotification(_ name: Notification.Name) -> NotificationCenter.Publisher {
//    #if DEBUG
//    L.og.info("🗡️🗡️ receiveNotification: \(name.rawValue)")
//    #endif
    return NotificationCenter.default.publisher(for: name)
}

extension Notification.Name {
    
    static var blockListUpdated: Notification.Name {
        return Notification.Name("blockListUpdated")
    }
    
    static var muteListUpdated: Notification.Name {
        return Notification.Name("muteListUpdated")
    }
    
    static var blockedHashtagsUpdated: Notification.Name {
        return Notification.Name("blockedHashtagsUpdated")
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
    
    static var addedNotes: Notification.Name {
        return Notification.Name("addedNotes")
    }
    
    static var shouldScrollToTop: Notification.Name {
        return Notification.Name("shouldScrollToTop")
    }
    
    static var shouldScrollToFirstUnread: Notification.Name {
        return Notification.Name("shouldScrollToRecent")
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
    
    static var updateNotificationsCount: Notification.Name {
        return Notification.Name("updateNotificationsCount")
    }
    
    static var listStatus: Notification.Name {
        return Notification.Name("listStatus")
    }
    
    static var fullScreenView: Notification.Name {
        return Notification.Name("fullScreenView")
    }    
    
    static var fullScreenView17: Notification.Name {
        return Notification.Name("fullScreenView17")
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
         
    static var navigateToOnDetail: Notification.Name {
        return Notification.Name("navigateToOnDetail")
    }
     
    static var newPostSaved: Notification.Name {
        return Notification.Name("newPostSaved")
    }
    
    static var publishingEvent: Notification.Name {
        return Notification.Name("publishingEvent")
    }
    
    static var unpublishedNRPost: Notification.Name {
        return Notification.Name("unpublishedNRPost")
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
    
    static var followingAdded: Notification.Name {
        return Notification.Name("followingAdded")
    }
    
    static var explorePubkeysChanged: Notification.Name {
        return Notification.Name("explorePubkeysChanged")
    }
        
    static var listPubkeysChanged: Notification.Name {
        return Notification.Name("listPubkeysChanged")
    }
    
    static var listRelaysChanged: Notification.Name {
        return Notification.Name("listRelaysChanged")
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
        
    static var socketConnected: Notification.Name {
        return Notification.Name("socketConnected")
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
    
    static var noNewEventsInDatabase: Notification.Name {
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
    static var importedPrioMessage: Notification.Name {
        return Notification.Name("importedPrioMessage")
    }
    
    static var receivedMessage: Notification.Name {
        return Notification.Name("receivedMessage")
    }
    
    static var newMentions: Notification.Name {
        return Notification.Name("newMentions")
    }   
    
    static var unreadNewPosts: Notification.Name {
        return Notification.Name("unreadNewPosts")
    }
    
    static var newReposts: Notification.Name {
        return Notification.Name("newReposts")
    }
    
    static var newReactions: Notification.Name {
        return Notification.Name("newReactions")
    }
    
    static var newZaps: Notification.Name {
        return Notification.Name("newZaps")
    }
    
    static var newFollowers: Notification.Name {
        return Notification.Name("newFollowers")
    }

    static var contactSaved: Notification.Name {
        return Notification.Name("contactSaved")
    }
    
    static var postAction: Notification.Name {
        return Notification.Name("postAction")
    }
    
    static var pong: Notification.Name {
        return Notification.Name("pong")
    }
    
    static var showNoteMenu: Notification.Name {
        return Notification.Name("showNoteMenu")
    }
    
    static var notificationsTabAppeared: Notification.Name {
        return Notification.Name("notificationsTabAppeared")
    }
    
    static var nwcCallbackReceived: Notification.Name {
        return Notification.Name("nwcCallbackReceived")
    }
      
    static var nwcInfoReceived: Notification.Name {
        return Notification.Name("nwcInfoReceived")
    }
    
    static var lightningStrike: Notification.Name {
        return Notification.Name("lightningStrike")
    }
    
    static var scenePhaseActive: Notification.Name {
        return Notification.Name("scenePhaseActive")
    }
    static var scenePhaseBackground: Notification.Name {
        return Notification.Name("scenePhaseBackground")
    }
    
    static var scrollingUp: Notification.Name {
        return Notification.Name("scrollingUp")
    }
    
    static var scrollingDown: Notification.Name {
        return Notification.Name("scrollingDown")
    }
    
    static var sharePostScreenshot: Notification.Name {
        return Notification.Name("sharePostScreenshot")
    }
    
    static var shareWeblink: Notification.Name {
        return Notification.Name("shareWeblink")
    }
    
    static var showZapCustomizerSheet: Notification.Name {
        return Notification.Name("showZapCustomizerSheet")
    }
    
    static var sendCustomZap: Notification.Name {
        return Notification.Name("sendCustomZap")
    }
    
    static var showMiniProfile: Notification.Name {
        return Notification.Name("showMiniProfile")
    }
    
    static var dismissMiniProfile: Notification.Name {
        return Notification.Name("dismissMiniProfile")
    }
    
    static var scrollToDetail: Notification.Name {
        return Notification.Name("scrollToDetail")
    }
    
    static var showFeedToggles: Notification.Name {
        return Notification.Name("showFeedToggles")
    }
    static var showDMToggles: Notification.Name {
        return Notification.Name("showDMToggles")
    }
    
    static var didTapTab: Notification.Name {
        return Notification.Name("didTapTab")
    }
    
    static var showingSomeoneElsesFeed: Notification.Name {
        return Notification.Name("showingSomeoneElsesFeed")
    }
    
    static var WoTReady: Notification.Name {
        return Notification.Name("WoTReady")
    }
    
    static var didSend: Notification.Name {
        return Notification.Name("didSend")
    }
    
    static var triggerDM: Notification.Name {
        return Notification.Name("triggerDM")
    } 
    
    static var preloadNewDMInfo: Notification.Name {
        return Notification.Name("preloadNewDMInfo")
    }
    
    static var showImposterDetails: Notification.Name {
        return Notification.Name("showImposterDetails")
    }
    
    static var dynamicTextChanged: Notification.Name {
        return Notification.Name("dynamicTextChanged")
    }
    
    static var firstConnection: Notification.Name {
        return Notification.Name("firstConnection")
    }
    
    static var lastDisconnection: Notification.Name {
        return Notification.Name("lastDisconnection")
    }
}
