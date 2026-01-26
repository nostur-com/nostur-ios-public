//
//  Helpers.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/09/2025.
//

import SwiftUI

func selectedTab() -> String {
    UserDefaults.standard.string(forKey: "selected_tab") ?? "Main"
}

func setSelectedTab(_ tab: String) {
    UserDefaults.standard.set(tab, forKey: "selected_tab")
    if IS_CATALYST && SettingsStore.shared.proMode {
        MacColumnsVM.shared.selectedTab = tab
    }
}

func selectedSubTab() -> String {
    UserDefaults.standard.string(forKey: "selected_subtab") ?? "Following"
}

func setSelectedNotificationsTab(_ notificationsTab: String) {
    UserDefaults.standard.set(notificationsTab, forKey: "selected_notifications_tab")
    if IS_CATALYST && SettingsStore.shared.proMode {
        MacColumnsVM.shared.selectedNotificationsTab = notificationsTab
    }
}

func setSelectedSubTab(_ subTab: String) {
    UserDefaults.standard.set(subTab, forKey: "selected_subtab")
}


func selectedListId() -> String {
    UserDefaults.standard.string(forKey: "selected_listId") ?? ""
}

func homeTabNavigationTitle(_ selectedList: CloudFeed? = nil) -> String {
    if selectedSubTab() == "List" {
        return (selectedList?.name_ ?? String(localized: "List"))
    }
    if selectedSubTab() == "Following" {
        return String(localized: "Following", comment: "Tab title for feed of people you follow")
    }
    if selectedSubTab() == "Picture" {
        return String(localized: "Photos", comment: "Tab title for photos feed of people you follow")
    }
    if selectedSubTab() == "Yak" {
        return String(localized: "Yaks", comment: "Tab title for voice messages feed of people you follow")
    }
    if selectedSubTab() == "Vine" {
        return String(localized: "diVines", comment: "Tab title for short videos feed of people you follow")
    }
    if selectedSubTab() == "Explore" {
        return String(localized: "Explore", comment: "Tab title for the Explore feed")
    }
    if selectedSubTab() == "Emoji" {
        return String(localized: "Funny", comment: "Tab title for the Funny feed")
    }
    if selectedSubTab() == "Zapped" {
        return String(localized: "Zapped", comment: "Tab title for the Zapped feed")
    }
    if selectedSubTab() == "Hot" {
        return String(localized: "Hot", comment: "Tab title for the Hot feed")
    }
    if selectedSubTab() == "DiscoverLists" {
        return String(localized: "Follow Packs & Lists", comment: "Tab title for the Discover Lists feed")
    }
    if selectedSubTab() == "Streams" {
        return String(localized: "Live Streams", comment: "Tab title for the Live Streams feed")
    }
    if selectedSubTab() == "Gallery" {
        return String(localized: "Gallery", comment: "Tab title for the Gallery feed")
    }
    if selectedSubTab() == "Articles" {
        return String(localized: "Reads", comment: "Tab title for the Reads (Articles) feed")
    }
    return String(localized: "Feed", comment: "Tab title for a feed")
}

func goToDMs() {
    // DMs moved to sidebar on iOS 26 (but not on desktop catalyst)
    if #available(iOS 26.0, *), !IS_CATALYST {
        setSelectedTab("Main")
        navigateToOnMain(ViewPath.DMs)
    }
    
    else { // older iOS, or catalyst (both pre/post 26)
        setSelectedTab("Messages")
    }
}

func nxLogChanges<T: View>(of viewType: T.Type) {
    if #available(iOS 17.1, *) {
        viewType._logChanges()
    } else {
        viewType._printChanges()
    }
}
