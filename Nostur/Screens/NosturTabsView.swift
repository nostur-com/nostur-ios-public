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
    
    var body: some View {
        let _ = Self._printChanges()
        HStack {
            VStack {
                AppTopBar()
                    .padding(5)
                
                TabView(selection: $selectedTab) {
                    FollowingAndExplore()
                    .tabItem { Image(systemName: "house") }
                    .tag("Main")
                
                    NotificationsContainer()
                    .tabItem { Image(systemName: "bell.fill") }
                    .tag("Notifications")
                    
                    Search()
                    .tabItem { Image(systemName: "magnifyingglass") }
                    .tag("Search")
                    

                    BookmarksContainer()
                    .tabItem { Image(systemName: "bookmark") }
                    .tag("Bookmarks")
                    
                    
                    ConfigurationView()
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
