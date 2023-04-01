//
//  ContentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import CoreData

struct NosturTabsView: View {
    //    @AppStorage("showReplies") var showReplies = true // TODO: Move to Timeline
    
    //    @EnvironmentObject var nav:NavigationModel
    @AppStorage("selected_tab") var selectedTab = "Main"
    @State var unread = 0
    @State var unreadDMs = 0
    
    var body: some View {
        let _ = Self._printChanges()
        HStack {
            VStack {
                TabView(selection: $selectedTab) {
                    FollowingAndExplore()
                        .tabItem { Image(systemName: "house") }
                        .tag("Main")
                    
                    NotificationsContainer()
                        .tabItem { Image(systemName: "bell.fill") }
                        .tag("Notifications")
                        .badge(unread)
                    
                    Search()
                        .tabItem { Image(systemName: "magnifyingglass") }
                        .tag("Search")
                    
                    
                    BookmarksAndPrivateNotes()
                        .tabItem { Image(systemName: "bookmark") }
                        .tag("Bookmarks")
                    
                    DirectMessagesContainer()
                        .tabItem { Image(systemName: "envelope.fill") }
                        .tag("Messages")
                        .badge(unreadDMs)
                    
                    
                    //                    ConfigurationView() // TODO: MOVE TO SETTINGS
                    //                    .tabItem { Image(systemName: "server.rack") }
                    //                    .tag("Configuration")
                }
                .onTapGesture(count: 2) { location in
                    let fixedHeightFromBottom: CGFloat = 130 // Adjust this value as needed
                    if location.y >= UIScreen.main.bounds.height - fixedHeightFromBottom {
                        let tabWidth = UIScreen.main.bounds.width / CGFloat(5 + 1)
                        let tappedTab = Int((location.x + tabWidth / 2) / tabWidth)
                        if (selectedTab == "Main") && (tappedTab == 1) {
                            sendNotification(.shouldScrollToLast)
                        }
                        else {
                            selectedTab = ["Main", "Notifications", "Search", "Bookmarks", "Messages"][max(0,tappedTab-1)]
                        }
                    }
                }
                .withSheets()
            }
            .frame(maxWidth: 600)
            if UIDevice.current.userInterfaceIdiom == .pad {
                TabbedDetailContainer()
            }
        }
        .onReceive(receiveNotification(.updateNotificationsCount)) { notification in
            unread = (notification.object as! Int)
        }
        .onReceive(receiveNotification(.updateDMsCount)) { notification in
            unreadDMs = (notification.object as! Int)
        }
        //        .ignoresSafeArea()
    }
    
}

struct ContentView_Previews: PreviewProvider {
    //    @State static var showMenu = false
    //    @State static var selectedTab = "Timeline"
    //
    //    @State static var timelinePath = NavigationPath()
    //    @State static var searchPath = NavigationPath()
    //    @State static var accountsPath = NavigationPath()
    //    @State static var bookmarksPath = NavigationPath()
    //    @State static var notificationsPath = NavigationPath()
    //    @State static var messagesPath = NavigationPath()
    //    @State static var configurationPath = NavigationPath()
    //    @State static var detailPath = NavigationPath()
    //    @State static var showSidebar = false
    
    static var previews: some View {
        NosturTabsView()
            .withPreviewEnvironment()
    }
}
