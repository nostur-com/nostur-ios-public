//
//  MainTabs.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/08/2025.
//

import SwiftUI

struct MainTabs: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var dm: DirectMessageViewModel
    @AppStorage("selected_tab") private var selectedTab = "Main"
    @State private var unread: Int = 0
    
    var body: some View {
#if DEBUG
        let _ = Self._printChanges()
#endif
        VStack {
            NoInternetConnectionBanner()
            TabView(selection: $selectedTab.onUpdate { oldTab, newTab in
                tabTapped(newTab, oldTab: oldTab)
            }) {
                HomeTab()
//                    .environment(\.horizontalSizeClass, horizontalSizeClass)
                    .tabItem {
                        Image(systemName: "house")
                    }
                    .tag("Main")
                    .nosturTabsCompat(theme: theme)

                BookmarksTab()
//                    .environment(\.horizontalSizeClass, horizontalSizeClass)
                    .tabItem {
                        Image(systemName: "bookmark")
                    }
                    .tag("Bookmarks")
                    .nosturTabsCompat(theme: theme)
                
                
                Search()
//                    .environment(\.horizontalSizeClass, horizontalSizeClass)
                    .tabItem {
                        Image(systemName: "magnifyingglass")
                    }
                    .labelStyle(.iconOnly)
                    .tag("Search")
                    .nosturTabsCompat(theme: theme)
                
                NotificationsContainer()
//                    .environment(\.horizontalSizeClass, horizontalSizeClass)
                    .tabItem {
                        Image(systemName: "bell.fill")
                    }
                    .labelStyle(.iconOnly)
                    .tag("Notifications")
                    .badge(unread)
                    .nosturTabsCompat(theme: theme)

                DMContainer()
//                    .environment(\.horizontalSizeClass, horizontalSizeClass)
                    .tabItem {
                        Image(systemName: "envelope.fill")
                    }
                    .tag("Messages")
                    .badge((dm.unread + dm.newRequests))
                    .nosturTabsCompat(theme: theme)
            }
            
            .withSheets() // Move .sheets to each (NB)NavigationStack?
            .edgesIgnoringSafeArea(.all)
        }
        
        .onChange(of: selectedTab) { newValue in
            if newValue == "Notifications" {
                
                // If there is only one tab with unread notifications, go to that tab
                if NotificationsViewModel.shared.unread > 0 {
                    if NotificationsViewModel.shared.unreadMentions > 0 {
                        UserDefaults.standard.setValue("Mentions", forKey: "selected_notifications_tab")
                    }
                    else if NotificationsViewModel.shared.unreadNewPosts > 0 {
                        UserDefaults.standard.setValue("New Posts", forKey: "selected_notifications_tab")
                    }
                    else if NotificationsViewModel.shared.unreadReactions > 0 {
                        UserDefaults.standard.setValue("Reactions", forKey: "selected_notifications_tab")
                    }
                    else if NotificationsViewModel.shared.unreadZaps > 0 {
                        UserDefaults.standard.setValue("Zaps", forKey: "selected_notifications_tab")
                    }
                    else if NotificationsViewModel.shared.unreadReposts > 0 {
                        UserDefaults.standard.setValue("Reposts", forKey: "selected_notifications_tab")
                    }
                    else if NotificationsViewModel.shared.unreadNewFollowers > 0 {
                        UserDefaults.standard.setValue("Followers", forKey: "selected_notifications_tab")
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    sendNotification(.notificationsTabAppeared) // use for resetting unread count
                }
            }
        }
        
        .onReceive(NotificationsViewModel.shared.unreadPublisher) { unread in
            if unread != self.unread {
                self.unread = unread
            }
        }
    }
    
    private func tabTapped(_ tabName: String, oldTab: String) {
        
        // Only do something if we are already on same the tab
        guard oldTab == tabName else { return }

        // For main, we scroll to first unread
        // but depends on condition with values only known in FollowingAndExplore
        sendNotification(.didTapTab, tabName)

        // pop navigation stack back to root
        sendNotification(.clearNavigation, tabName)
    }
}

#Preview {
    MainTabs()
}
