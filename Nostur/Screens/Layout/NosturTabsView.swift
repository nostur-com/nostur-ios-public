//
//  NosturTabsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI

struct NosturTabsView: View {
    @StateObject private var dim = DIMENSIONS()
    @AppStorage("selected_tab") var selectedTab = "Main"
    @State var unread = 0
    @State var unreadDMs = 0
    
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
                TabView(selection: $selectedTab.onUpdate { tabTapped(selectedTab) }) {
                    MainView()
                        .tabItem { Image(systemName: "house") }
                        .tag("Main")
                    
//                    DiscoverCommunities()
//                        .tabItem { Image(systemName: "person.3.fill")}
//                        .tag("Communities")
                    
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
                    
//                    RelayIntelTest()
                    
                    DirectMessagesContainer()
                        .tabItem { Image(systemName: "envelope.fill") }
                        .tag("Messages")
                        .badge(unreadDMs)
                }
                .withSheets()
            }
            .frame(maxWidth: 600)
            .environmentObject(dim)
            .edgesIgnoringSafeArea(.all)
            if UIDevice.current.userInterfaceIdiom == .pad {
                DetailPane()
            }
        }
        .background(Color("ListBackground"))
        .withLightningEffect()
        .onChange(of: selectedTab) { newValue in
            if !IS_CATALYST {
                if newValue == "Main" {
                    sendNotification(.scrollingUp) // To show the navigation/toolbar
                }
            }
            if newValue == "Notifications" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    sendNotification(.notificationsTabAppeared) // use for resetting unread count
                }
            }
        }
        .onReceive(receiveNotification(.updateNotificationsCount)) { notification in
            unread = (notification.object as! Int)
        }
        .onReceive(receiveNotification(.updateDMsCount)) { notification in
            unreadDMs = (notification.object as! Int)
        }
    }

    private func tabTapped(_ tabName:String) {
        guard selectedTab == "Main" else { return } // Only trigger if we are already on "Main"
        if tabName == "Main" {
            sendNotification(.shouldScrollToFirstUnread)
            // TODO: FIX DOUBLE TAP TO SCROLL TO TOP
        }
    }
}


extension Binding {
    func onUpdate(_ closure: @escaping () -> Void) -> Binding<Value> {
        Binding(get: {
            wrappedValue
        }, set: { newValue in
            wrappedValue = newValue
            closure()
        })
    }
}
