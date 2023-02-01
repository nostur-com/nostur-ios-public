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
    
    @State var mainTimelinePath = NavigationPath()
    @State var searchPath = NavigationPath()
    @State var accountsPath = NavigationPath()
    @State var notificationsPath = NavigationPath()
    @State var messagesPath = NavigationPath()
    
    var body: some View {
        VStack {
            TabView(selection: $selectedTab) {
                NavigationStack(path: $mainTimelinePath) {
                    if (ns.followingPublicKeys.count != 0) {
                        MainTimelineView(showReplies: true, followingPubkeys: ns.followingPublicKeys, showMenu: $showMenu)
                            .withNavigationDestinations()
                    } else {
                        Text(" Ey yo")
                    }
                }
                .tabItem { Image(systemName: "house.fill") }.tag("MainTimeline")
                
                NavigationStack {
                    AccountListView()
                        .withNavigationDestinations()
                    Spacer()
                }
                .tabItem {
                    Image(systemName: "person.badge.key.fill")
                }.tag("Accounts")
                
                NavigationStack {
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
                
                NavigationStack {
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
    static var previews: some View {
        NosturTabsView(showMenu: $showMenu, selectedTab: $selectedTab)
            .withPreviewEnvironment()
    }
}
