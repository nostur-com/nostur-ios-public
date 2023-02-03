//
//  ContentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import CoreData

struct NosturTabsView: View {

    @AppStorage("showReplies") var showReplies = true // TODO: Move to Timeline
    @Binding var showMenu:Bool
    @EnvironmentObject var ns:NosturState
    
    @Binding var selectedTab:String
    
    @Binding var timelinePath:NavigationPath
    @Binding var searchPath:NavigationPath
    @Binding var accountsPath:NavigationPath
    @Binding var bookmarksPath:NavigationPath
    @Binding var notificationsPath:NavigationPath
    @Binding var messagesPath:NavigationPath
    @Binding var configurationPath:NavigationPath
    
    var body: some View {
        VStack {
            TabView(selection: $selectedTab) {
                NavigationStack(path: $timelinePath) {
                    if (ns.followingPublicKeys.count != 0) {
                        Timeline(showReplies: true, followingPubkeys: ns.followingPublicKeys, showMenu: $showMenu, account: ns.account!)
                            .withNavigationDestinations()
                    } else {
                        Text(" Ey yo")
                    }
                }
                .tabItem { Image(systemName: "house.fill") }.tag("Timeline")
                
                NavigationStack(path: $accountsPath) {
                    AccountListView()
                        .withNavigationDestinations()
                    Spacer()
                }
                .tabItem {
                    Image(systemName: "person.badge.key.fill")
                }.tag("Accounts")
                
                NavigationStack(path: $bookmarksPath) {
                    if (ns.account != nil) {
                        BookmarksView(account: ns.account!)
                            .withNavigationDestinations()
                    }
                    else {
                        Text("Select account account first on accounts tab.")
                    }
                    Spacer()
                }
                .tabItem { Image(systemName: "bookmark.circle") }
                .tag("Bookmarks")
                
                NavigationStack(path: $configurationPath) {
                    ConfigurationView()
                        .withNavigationDestinations()
                    Spacer()
                }
                .tabItem { Image(systemName: "server.rack") }
                .tag("Configuration")
            }
//            .background(.regularMaterial)
        }
    }
    
}

struct ContentView_Previews: PreviewProvider {
    @State static var showMenu = false
    @State static var selectedTab = "MainTimeline"
    
    @State static var timelinePath = NavigationPath()
    @State static var searchPath = NavigationPath()
    @State static var accountsPath = NavigationPath()
    @State static var bookmarksPath = NavigationPath()
    @State static var notificationsPath = NavigationPath()
    @State static var messagesPath = NavigationPath()
    @State static var configurationPath = NavigationPath()
    
    static var previews: some View {
        NosturTabsView(showMenu: $showMenu, selectedTab: $selectedTab, timelinePath: $timelinePath, searchPath: $searchPath, accountsPath: $accountsPath, bookmarksPath: $bookmarksPath, notificationsPath: $notificationsPath, messagesPath: $messagesPath, configurationPath: $configurationPath)
            .withPreviewEnvironment()
    }
}
