//
//  NosturTabsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI

struct NosturTabsView: View {
    @EnvironmentObject var theme:Theme
    @StateObject private var dim = DIMENSIONS()
    @AppStorage("selected_tab") var selectedTab = "Main"
    @AppStorage("selected_notifications_tab") var selectedNotificationsTab = "Posts"
    @State var unread = 0
    @State var showTabBar = true
    @ObservedObject var ss:SettingsStore = .shared
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
//    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    var body: some View {
//        let _ = Self._printChanges()
        HStack {
            VStack {
                Color.clear.frame(height: 0)
                    .modifier(SizeModifier())
                    .onPreferenceChange(SizePreferenceKey.self) { size in
                        guard size.width > 0 else { return }
                        dim.listWidth = size.width
                    }
                TabView(selection: $selectedTab.onUpdate { oldTab, newTab in
                    tabTapped(newTab, oldTab: oldTab)
                }) {
                    MainView()
                        .tabItem { Image(systemName: "house") }
                        .tag("Main")
                        .toolbar(!ss.autoHideBars || showTabBar ? .visible : .hidden, for: .tabBar)
                    
//                    DiscoverCommunities()
//                        .tabItem { Image(systemName: "person.3.fill")}
//                        .tag("Communities")
                    
                    NotificationsContainer()
                        .tabItem { Image(systemName: "bell.fill") }
                        .tag("Notifications")
                        .badge(unread)
                        .toolbar(!ss.autoHideBars || showTabBar ? .visible : .hidden, for: .tabBar)
                    
                    Search()
                        .tabItem { Image(systemName: "magnifyingglass") }
                        .tag("Search")
                        .toolbar(!ss.autoHideBars || showTabBar ? .visible : .hidden, for: .tabBar)
                    
                    BookmarksAndPrivateNotes()
                        .tabItem { Image(systemName: "bookmark") }
                        .tag("Bookmarks")
                        .toolbar(!ss.autoHideBars || showTabBar ? .visible : .hidden, for: .tabBar)
                    
                    DMContainer()
                        .tabItem { Image(systemName: "envelope.fill") }
                        .tag("Messages")
                        .badge((dm.unread + dm.newRequests))
                }
                .withSheets()
            }
            .frame(maxWidth: 600)
            .environmentObject(dim)
            .edgesIgnoringSafeArea(.all)
            if UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular {
                DetailPane()
            }
        }
        .contentShape(Rectangle())
        .background(theme.listBackground)
        .withLightningEffect()
        .onChange(of: selectedTab) { newValue in
            if !IS_CATALYST {
                if newValue == "Main" {
                    sendNotification(.scrollingUp) // To show the navigation/toolbar
                }
            }
            if newValue == "Notifications" {
                
                // If there is only one tab with unread notifications, go to that tab
                if NotificationsManager.shared.unread > 0 {
                    if NotificationsManager.shared.unreadMentions == NotificationsManager.shared.unread {
                        selectedNotificationsTab = "Posts"
                    }
                    else if NotificationsManager.shared.unreadReactions == NotificationsManager.shared.unread {
                        selectedNotificationsTab = "Reactions"
                    }
                    else if NotificationsManager.shared.unreadZaps == NotificationsManager.shared.unread {
                        selectedNotificationsTab = "Zaps"
                    }
                    // 2 tabs have unread, go to Zaps or Posts
                    else if NotificationsManager.shared.unreadMentions == 0 {
                        selectedNotificationsTab = "Zaps"
                    }
                    else if NotificationsManager.shared.unreadReactions == 0 {
                        selectedNotificationsTab = "Posts"
                    }
                    else if NotificationsManager.shared.unreadZaps == 0 {
                        selectedNotificationsTab = "Posts"
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    sendNotification(.notificationsTabAppeared) // use for resetting unread count
                }
            }
        }
        .onReceive(receiveNotification(.updateNotificationsCount)) { notification in
            unread = (notification.object as! Int)
        }
        .onReceive(receiveNotification(.scrollingUp)) { _ in
            guard !IS_CATALYST && ss.autoHideBars else { return }
            withAnimation {
                showTabBar = true
            }
        }
        .onReceive(receiveNotification(.scrollingDown)) { _ in
            guard !IS_CATALYST && ss.autoHideBars else { return }
            withAnimation {
                showTabBar = false
            }
        }
//        .overlay(alignment: .topLeading) {
//            VStack {
//                Text("h: \(horizontalSizeClass.debugDescription)")
//                Text("v: \(verticalSizeClass.debugDescription)")
//                Spacer()
//            }
//        }
    }

    private func tabTapped(_ tabName:String, oldTab:String) {
        
        // Only do something if we are already on same the tab
        guard oldTab == tabName else { return }

        // For main, we scroll to first unread
        // but depends on condition with values only known in FollowingAndExplore
        sendNotification(.didTapTab, tabName)

        // pop navigation stack back to root
        sendNotification(.clearNavigation, tabName)
    }
}


extension Binding {
    func onUpdate(_ closure: @escaping (Value, Value) -> Void) -> Binding<Value> {
        Binding(get: {
            wrappedValue
        }, set: { newValue in
            let oldValue = wrappedValue
            wrappedValue = newValue
            closure(oldValue, newValue)
        })
    }
}
