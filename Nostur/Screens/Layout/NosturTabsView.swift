//
//  NosturTabsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import NavigationBackport
@_spi(Advanced) import SwiftUIIntrospect

struct NosturTabsView: View {
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dm: DirectMessageViewModel
    
    @AppStorage("selected_tab") private var selectedTab = "Main"
    
    private var selectedNotificationsTab: String {
        get { UserDefaults.standard.string(forKey: "selected_notifications_tab") ?? "Mentions" }
    }

    @State private var unread: Int = 0
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        Zoomable {
            HStack {
                AvailableWidthContainer {
                    VStack {
                        NoInternetConnectionBanner()
                        TabView(selection: $selectedTab.onUpdate { oldTab, newTab in
                            tabTapped(newTab, oldTab: oldTab)
                        }) {
                            MainView()
                                .environment(\.horizontalSizeClass, horizontalSizeClass)
//                                .environmentObject(la)
                                .tabItem { Label("", systemImage: "house") }
                                .tag("Main")
                                .nosturTabsCompat(themes: themes)
                            
        //                    DiscoverCommunities()
        //                        .tabItem { Label("Communities", systemImage: "person.3.fill")}
        //                        .tag("Communities")
                                .nosturTabsCompat(themes: themes)

                            BookmarksAndPrivateNotes()
                                .environment(\.horizontalSizeClass, horizontalSizeClass)
                                .tabItem { Label("", systemImage: "bookmark") }
                                .tag("Bookmarks")
                                .nosturTabsCompat(themes: themes)
                            
                            
                            Search()
                                .environment(\.horizontalSizeClass, horizontalSizeClass)
                                .tabItem { Label("", systemImage: "magnifyingglass") }
                                .tag("Search")
                                .nosturTabsCompat(themes: themes)
                            
                            NotificationsContainer()
                                .environment(\.horizontalSizeClass, horizontalSizeClass)
                                .tabItem { Label("", systemImage: "bell.fill") }
                                .tag("Notifications")
                                .badge(unread)
                                .nosturTabsCompat(themes: themes)

                            DMContainer()
                                .environment(\.horizontalSizeClass, horizontalSizeClass)
                                .tabItem { Label("", systemImage: "envelope.fill") }
                                .tag("Messages")
                                .badge((dm.unread + dm.newRequests))
                                .nosturTabsCompat(themes: themes)
                        }
                        .environment(\.horizontalSizeClass, .compact)
                        .withSheets() // Move .sheets to each (NB)NavigationStack?
                        .edgesIgnoringSafeArea(.all)
                    }
                }
                .frame(maxWidth: 600)
                .overlay(alignment: .center) {
                    OverlayVideo()
                        .edgesIgnoringSafeArea(.bottom)
                }
                if UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular {
                    AvailableWidthContainer {
                        DetailPane()
                    }
                }
            }
            .contentShape(Rectangle())
            .background(themes.theme.listBackground)
            .withLightningEffect()
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
            .task {
                if SettingsStore.shared.receiveLocalNotifications {
                    requestNotificationPermission()
                }
            }
            .onReceive(NotificationsViewModel.shared.unreadPublisher) { unread in
                if unread != self.unread {
                    self.unread = unread
                }
            }
        }
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


struct NoInternetConnectionBanner: View {
    @EnvironmentObject private var networkMonitor:NetworkMonitor
    
    var body: some View {
        if networkMonitor.isDisconnected {
            Text("\(Image(systemName: "wifi.exclamationmark")) No internet connection")
                .font(.caption)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(5)
                .background(.red)
        }
        else {
            EmptyView()
        }
    }
}


struct WithNavigationIf<Content: View>: View {
    
    let condition: Bool
    let content: Content
        
    init(condition: Bool, @ViewBuilder _ content: () -> Content) {
        self.condition = condition
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            if condition {
                NBNavigationStack {
                    content
                }
            }
            else {
                content
            }
        }
    }
}
