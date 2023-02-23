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
    @Binding var showSidebar:Bool
    
    
    @Binding var selectedTab:String
    
    @Binding var timelinePath:NavigationPath
    @Binding var searchPath:NavigationPath
    @Binding var accountsPath:NavigationPath
    @Binding var bookmarksPath:NavigationPath
    @Binding var notificationsPath:NavigationPath
    @Binding var messagesPath:NavigationPath
    @Binding var configurationPath:NavigationPath
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
            TabView(selection: $selectedTab) {
                NavigationStack(path: $timelinePath) {
//                    Timeline()
//                    TLController()
//                    TL4(pubkeys: ns.followingPublicKeys, context: viewContext, showMenu: $showMenu)
//                    Text("hi")
                    TL4W()
                        .withNavigationDestinations()
                }
                .tabItem { Image(systemName: "house") }.tag("Timeline")
                                
                NavigationStack(path: $notificationsPath) {
                    NotificationsW()
                        .withNavigationDestinations()
                    Spacer()
                }
                .tabItem { Image(systemName: "bell.fill") }
                .tag("Notifications")
                
                NavigationStack(path: $searchPath) {
                    Search()
                        .withNavigationDestinations()
                    Spacer()
                }
                .tabItem { Image(systemName: "magnifyingglass") }
                .tag("Search")
                
                NavigationStack(path: $bookmarksPath) {
                    BookmarksW()
                        .withNavigationDestinations()
                    Spacer()
                }
                .tabItem { Image(systemName: "bookmark") }
                .tag("Bookmarks")
                
                NavigationStack(path: $configurationPath) {
                    ConfigurationView()
                        .withNavigationDestinations()
                    Spacer()
                }
                .tabItem { Image(systemName: "server.rack") }
                .tag("Configuration")
            }
            .background(.regularMaterial)
        }
    }
    
}

struct ContentView_Previews: PreviewProvider {
    @State static var showMenu = false
    @State static var selectedTab = "Timeline"
    
    @State static var timelinePath = NavigationPath()
    @State static var searchPath = NavigationPath()
    @State static var accountsPath = NavigationPath()
    @State static var bookmarksPath = NavigationPath()
    @State static var notificationsPath = NavigationPath()
    @State static var messagesPath = NavigationPath()
    @State static var configurationPath = NavigationPath()
    @State static var showSidebar = false
    
    static var previews: some View {
//        NosturTabsView(selectedTab: $selectedTab, timelinePath: $timelinePath, searchPath: $searchPath, accountsPath: $accountsPath, bookmarksPath: $bookmarksPath, notificationsPath: $notificationsPath, messagesPath: $messagesPath, configurationPath: $configurationPath)
        NosturTabsView(showSidebar: $showSidebar, selectedTab: $selectedTab, timelinePath: $timelinePath, searchPath: $searchPath, accountsPath: $accountsPath, bookmarksPath: $bookmarksPath, notificationsPath: $notificationsPath, messagesPath: $messagesPath, configurationPath: $configurationPath)
            .withPreviewEnvironment()
    }
}
