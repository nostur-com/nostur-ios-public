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
    
    @EnvironmentObject var nav:NavigationModel
    
    var body: some View {
        let _ = Self._printChanges()
        HStack {
            VStack {
                AppTopBar()
                    .padding(5)
                TabView(selection: $nav.selectedTab) {
                    NavigationStack(path: $nav.mainPath) {
                        FollowingAndExplore()
                            .withNavigationDestinations()
                    }
                    .tabItem { Image(systemName: "house") }
                    .tag("Main")
                    
                    NavigationStack(path: $nav.notificationsPath) {
                        NotificationsContainer()
                            .withNavigationDestinations()
                        Spacer()
                    }
                    .tabItem { Image(systemName: "bell.fill") }
                    .tag("Notifications")
                    
                    NavigationStack(path: $nav.searchPath) {
                        Search()
                            .withNavigationDestinations()
                        Spacer()
                    }
                    .tabItem { Image(systemName: "magnifyingglass") }
                    .tag("Search")
                    
                    NavigationStack(path: $nav.bookmarksPath) {
                        BookmarksContainer()
                            .withNavigationDestinations()
                        Spacer()
                    }
                    .tabItem { Image(systemName: "bookmark") }
                    .tag("Bookmarks")
                    
                    NavigationStack(path: $nav.configurationPath) {
                        ConfigurationView()
                            .withNavigationDestinations()
                        Spacer()
                    }
                    .tabItem { Image(systemName: "server.rack") }
                    .tag("Configuration")
                }
            }
//            .background(.regularMaterial)
            .frame(maxWidth: 600)
            if UIDevice.current.userInterfaceIdiom == .pad {
                TabbedDetailContainer()
            }
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
