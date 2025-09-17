//
//  MainTabs.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/08/2025.
//

import SwiftUI
import NavigationBackport

struct MainTabs: View {
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
                    .environment(\.horizontalSizeClass, horizontalSizeClass)
                    .tabItem {
                        Image(systemName: "house")
                    }
                    .tag("Main")
                    .nosturTabsCompat(theme: theme)

                BookmarksTab()
                    .environment(\.horizontalSizeClass, horizontalSizeClass)
                    .tabItem {
                        Image(systemName: "bookmark")
                    }
                    .tag("Bookmarks")
                    .nosturTabsCompat(theme: theme)
                
                
                Search()
                    .environment(\.horizontalSizeClass, horizontalSizeClass)
                    .tabItem {
                        Image(systemName: "magnifyingglass")
                    }
                    .labelStyle(.iconOnly)
                    .tag("Search")
                    .nosturTabsCompat(theme: theme)
                
                NotificationsContainer()
                    .environment(\.horizontalSizeClass, horizontalSizeClass)
                    .tabItem {
                        Image(systemName: "bell.fill")
                    }
                    .labelStyle(.iconOnly)
                    .tag("Notifications")
                    .badge(unread)
                    .nosturTabsCompat(theme: theme)

                DMContainer()
                    .environment(\.horizontalSizeClass, horizontalSizeClass)
                    .tabItem {
                        Image(systemName: "envelope.fill")
                    }
                    .tag("Messages")
                    .badge((dm.unread + dm.newRequests))
                    .nosturTabsCompat(theme: theme)
            }
            .modifier {
                if #available(iOS 26.0, *), selectedTab == "Main" {
                    $0.tabBarMinimizeBehavior(.onScrollDown)
//                      .tabViewBottomAccessory {
//                          
//                      }
                }
                else {
                    $0
                }
            }
            .environment(\.horizontalSizeClass, .compact)
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

// Old style tabbar doesn't work anymore on Tahoe / macOS 26. So we recreate our own
@available(iOS 26.0, *)
struct MainTabs26: View {
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var dm: DirectMessageViewModel
    @AppStorage("selected_tab") private var selectedTab = "Main"
    @State private var unread: Int = 0
    
    var body: some View {
#if DEBUG
        let _ = Self._printChanges()
#endif
        VStack {
            NoInternetConnectionBanner()
            ZStack {
                HomeTab()
                    .environment(\.horizontalSizeClass, horizontalSizeClass)
                    .tabItem {
                        Image(systemName: "house")
                    }
                    .tag("Main")
                    .opacity(selectedTab == "Main" ? 1 : 0)

                BookmarksTab()
                    .environment(\.horizontalSizeClass, horizontalSizeClass)
                    .tabItem {
                        Image(systemName: "bookmark")
                    }
                    .tag("Bookmarks")
                    .opacity(selectedTab == "Bookmarks" ? 1 : 0)
                
                
                Search()
                    .environment(\.horizontalSizeClass, horizontalSizeClass)
                    .tabItem {
                        Image(systemName: "magnifyingglass")
                    }
                    .labelStyle(.iconOnly)
                    .tag("Search")
                    .opacity(selectedTab == "Search" ? 1 : 0)
                
                NotificationsContainer()
                    .environment(\.horizontalSizeClass, horizontalSizeClass)
                    .tabItem {
                        Image(systemName: "bell.fill")
                    }
                    .labelStyle(.iconOnly)
                    .tag("Notifications")
                    .opacity(selectedTab == "Notifications" ? 1 : 0)

                DMContainer()
                    .environment(\.horizontalSizeClass, horizontalSizeClass)
                    .tabItem {
                        Image(systemName: "envelope.fill")
                    }
                    .tag("Messages")
                    .opacity(selectedTab == "Messages" ? 1 : 0)
            }
            .environment(\.horizontalSizeClass, .compact)
            
            
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
        
        .safeAreaInset(edge: .bottom) {
            HStack {
                DesktopTabButton(action: {
                    tabTapped("Main", oldTab: selectedTab)
                    selectedTab = "Main"
                }, title: "Home", systemImage: "house.fill", isActive: selectedTab == "Main")

                
                DesktopTabButton(action: {
                    tabTapped("Bookmarks", oldTab: selectedTab)
                    selectedTab = "Bookmarks"
                }, title: "Bookmarks", systemImage: "bookmark.fill", isActive: selectedTab == "Bookmarks")
                
                DesktopTabButton(action: {
                    tabTapped("Search", oldTab: selectedTab)
                    selectedTab = "Search"
                }, title: "Search", systemImage: "magnifyingglass", isActive: selectedTab == "Search")
              
                DesktopTabButton(action: {
                    tabTapped("Notifications", oldTab: selectedTab)
                    selectedTab = "Notifications"
                }, title: "Notifications", systemImage: "bell.fill", isActive: selectedTab == "Notifications")
                .badgeCompat(unread)
                
                DesktopTabButton(action: {
                    tabTapped("Messages", oldTab: selectedTab)
                    selectedTab = "Messages"
                }, title: "Messages", systemImage: "envelope.fill", isActive: selectedTab == "Messages")
                .badgeCompat((dm.unread + dm.newRequests))
            }
            .foregroundStyle(Color.white)
            .padding(5)
            .background(
                theme.listBackground
                    .glassEffect(.clear)
                    .clipShape(Capsule())
                    .shadow(color: theme.accent.opacity(0.5), radius: 10)
            )
            .padding(.bottom, 10)
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


@available(iOS 26.0, *)
struct DesktopTabButton: View {
    @Environment(\.theme) var theme
    public let action: () -> Void
    public let title: String
    public let systemImage: String
    public let isActive: Bool
    
    static private let BUTTON_WIDTH: CGFloat = 60
    
    var body: some View {
        Button(action: {
            action()
        }, label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.title)
                .frame(width: 44, alignment: .center)
                .padding(8)
                .glassEffect(isActive ? .regular.tint(theme.accent) : .clear, in: .capsule(style: .continuous))
                .foregroundStyle(isActive ? Color.white : theme.accent)
        })
    }
}

#Preview {
    PreviewContainer {
        NBNavigationStack {
            MainTabs()
        }
    }
}

@available(iOS 26.0, *)
#Preview("MainTabs26"){
    PreviewContainer {
        NBNavigationStack {
            MainTabs26()
        }
    }
}

@available(iOS 26.0, *)
#Preview("Custom Tab Bar") {
    @Previewable @Environment(\.theme) var theme
    @Previewable @State var selectedTab = "Main"
    
    HStack {
        DesktopTabButton(action: {
            selectedTab = "Main"
        }, title: "Home", systemImage: "house", isActive: selectedTab == "Main")

        
        DesktopTabButton(action: {
            selectedTab = "Bookmarks"
        }, title: "Bookmarks", systemImage: "bookmark", isActive: selectedTab == "Bookmarks")
        
        DesktopTabButton(action: {
            selectedTab = "Search"
        }, title: "Search", systemImage: "magnifyingglass", isActive: selectedTab == "Search")
      
        DesktopTabButton(action: {
            selectedTab = "Notifications"
        }, title: "Notifications", systemImage: "bell.fill", isActive: selectedTab == "Notifications")
        .badgeCompat(5)
        
        DesktopTabButton(action: {
            selectedTab = "Messages"
        }, title: "Messages", systemImage: "envelope.fill", isActive: selectedTab == "Messages")
        .badgeCompat(9)
    }
    .foregroundStyle(Color.white)
    .padding(5)
    .background(
        theme.listBackground
            .glassEffect(.clear)
            .clipShape(Capsule())
            .shadow(color: theme.accent.opacity(0.5), radius: 10)
    )
    
    .padding(.bottom, 10)
}
