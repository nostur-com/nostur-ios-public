//
//  NosturTabsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI

struct NosturTabsView: View {
    @EnvironmentObject private var theme:Theme
    @EnvironmentObject private var dm:DirectMessageViewModel
    @EnvironmentObject private var nvm:NotificationsViewModel

    @StateObject private var dim = DIMENSIONS()
    @AppStorage("selected_tab") private var selectedTab = "Main"
    @AppStorage("selected_notifications_tab") private var selectedNotificationsTab = "Mentions"

    @State private var showTabBar = true
    @ObservedObject private var ss:SettingsStore = .shared
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
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
                    Group {
                        MainView()
                            .tabItem { Image(systemName: "house") }
                            .tag("Main")
                        
    //                    DiscoverCommunities()
    //                        .tabItem { Image(systemName: "person.3.fill")}
    //                        .tag("Communities")
                        
                        NotificationsContainer()
                            .tabItem { Image(systemName: "bell.fill") }
                            .tag("Notifications")
                            .badge(nvm.unread)
                        
                        Search()
                            .tabItem { Image(systemName: "magnifyingglass") }
                            .tag("Search")
                        
                        BookmarksAndPrivateNotes()
                            .tabItem { Image(systemName: "bookmark") }
                            .tag("Bookmarks")
                            
                        
                        DMContainer()
                            .tabItem { Image(systemName: "envelope.fill") }
                            .tag("Messages")
                            .badge((dm.unread + dm.newRequests))
                    }
                    .toolbarBackground(theme.listBackground, for: .tabBar)
                    .toolbar(!ss.autoHideBars || showTabBar ? .visible : .hidden, for: .tabBar)
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
                if NotificationsViewModel.shared.unread > 0 {
                    if NotificationsViewModel.shared.unreadMentions > 0 {
                        selectedNotificationsTab = "Mentions"
                    }
                    else if NotificationsViewModel.shared.unreadReactions > 0 {
                        selectedNotificationsTab = "Reactions"
                    }
                    else if NotificationsViewModel.shared.unreadZaps > 0 {
                        selectedNotificationsTab = "Zaps"
                    }
                    else if NotificationsViewModel.shared.unreadReposts > 0{
                        selectedNotificationsTab = "Reposts"
                    }
                    else if NotificationsViewModel.shared.unreadNewFollowers > 0 {
                        selectedNotificationsTab = "Followers"
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    sendNotification(.notificationsTabAppeared) // use for resetting unread count
                }
            }
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
