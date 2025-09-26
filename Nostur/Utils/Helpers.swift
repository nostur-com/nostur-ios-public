//
//  Helpers.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/09/2025.
//

import Foundation

func selectedTab() -> String {
    UserDefaults.standard.string(forKey: "selected_tab") ?? "Main"
}

func selectedSubTab() -> String {
    UserDefaults.standard.string(forKey: "selected_subtab") ?? "Following"
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
    if selectedSubTab() == "Gallery" {
        return String(localized: "Gallery", comment: "Tab title for the Gallery feed")
    }
    if selectedSubTab() == "Articles" {
        return String(localized: "Reads", comment: "Tab title for the Reads (Articles) feed")
    }
    return String(localized: "Feed", comment: "Tab title for a feed")
}
