//
//  NotificationsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/02/2023.
//

import SwiftUI
import CoreData

struct NotificationsContainer: View {
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject var la:LoggedInAccount
    @AppStorage("selected_tab") private var selectedTab = "Main"
    @AppStorage("selected_notifications_tab") private var selectedNotificationsTab = "Mentions"
    @State private var navPath = NavigationPath()
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
//        let _ = Self._printChanges()
        NavigationStack(path: $navPath) {
            VStack {
                NotificationsView(account: la.account, tab: $selectedNotificationsTab, navPath: $navPath)
            }
            .background(themes.theme.listBackground)
            .withNavigationDestinations()
        }
        .onReceive(receiveNotification(.navigateTo)) { notification in
            let destination = notification.object as! NavigationDestination
            guard !IS_IPAD || horizontalSizeClass == .compact else { return }
            guard selectedTab == "Notifications" else { return }
            navPath.append(destination.destination)
        }
        .onReceive(receiveNotification(.clearNavigation)) { notification in
            navPath.removeLast(navPath.count)
        }
    }
}

struct NotificationsView: View {
    @ObservedObject public var account:Account
    @Binding public var tab:String
    @Binding public var navPath:NavigationPath
    
    @EnvironmentObject private var themes:Themes
    @EnvironmentObject var dim:DIMENSIONS
    @ObservedObject private var nvm:NotificationsViewModel = .shared
    @ObservedObject private var settings:SettingsStore = .shared
    
    @State private var markAsReadDelayer:Timer?
    @State private var showNotificationSettings = false
    
    @AppStorage("notifications_mute_reactions") private var muteReactions:Bool = false
    @AppStorage("notifications_mute_zaps") private var muteZaps:Bool = false
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        VStack(spacing:0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    TabButton(action: {
                        withAnimation {
                            tab = "Mentions"
                            nvm.markMentionsAsRead()
                        }
                    }, title: String(localized: "Mentions", comment:"Title of tab"), selected: tab == "Mentions", unread: nvm.unreadMentions)
                    
                    TabButton(action: {
                        withAnimation {
                            tab = "Reactions"
                            nvm.markReactionsAsRead()
                        }
                    }, title: String(localized: "Reactions", comment:"Title of tab"), selected: tab == "Reactions", unread: nvm.unreadReactions_, muted: nvm.muteReactions)
                    
                    TabButton(action: {
                        withAnimation {
                            tab = "Reposts"
                            nvm.markRepostsAsRead()
                        }
                    }, title: String(localized: "Reposts", comment:"Title of tab"), selected: tab == "Reposts", unread: nvm.unreadReposts_, muted: nvm.muteReposts)
                    
                    TabButton(action: {
                        withAnimation {
                            tab = "Zaps"
                            nvm.markZapsAsRead()
                        }
                    }, title: String(localized: "Zaps", comment:"Title of tab"), selected: tab == "Zaps", unread: nvm.muteZaps ? nvm.unreadFailedZaps_ : (nvm.unreadZaps_ + nvm.unreadFailedZaps_), muted: nvm.muteZaps)
                    
                    TabButton(action: {
                        withAnimation {
                            tab = "Followers"
                            nvm.markNewFollowersAsRead()
                        }
                    }, title: String(localized: "Followers", comment:"Title of tab"), selected: tab == "Followers", unread: nvm.unreadNewFollowers_, muted: nvm.muteNewFollowers)
                }
                .padding(.horizontal, 10)
                .frame(minWidth: dim.listWidth)
            }
            .frame(width: dim.listWidth)
            
            switch (tab) {
                case "Mentions", "Posts": // (old name was "Posts")
                    NotificationsMentions(navPath: $navPath)
                case "Reactions":
                    NotificationsReactions(navPath: $navPath)
                case "Reposts":
                    NotificationsReposts(navPath: $navPath)
                case "Zaps":
                    NotificationsZaps(pubkey: account.publicKey, navPath: $navPath)
                case "Followers":
                    NotificationsFollowers(pubkey: account.publicKey, navPath: $navPath)
                default:
                    EmptyView()
            }
            Spacer()
        }
        .onReceive(receiveNotification(.notificationsTabAppeared)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                markActiveTabAsRead(tab)
            }
        }
        .onChange(of: tab, perform: { newValue in
            guard tab != newValue else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                markActiveTabAsRead(newValue)
            }
        })
        .overlay(alignment: .bottom) {
            if settings.statusBubble {
                ProcessingStatus()
                    .opacity(0.85)
                    .padding(.bottom, 10)
            }
        }
//        .padding(.top, 5)
        .navigationTitle(String(localized: "Notifications"))
//        .navigationBarHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Image(systemName: "gearshape")
                    .foregroundColor(themes.theme.accent)
                    .onTapGesture {
                        showNotificationSettings.toggle()
                    }
            }
        }
        .overlay(alignment: .top) {
            if showNotificationSettings {
                NotificationSettings(showFeedSettings: $showNotificationSettings)
            }
        }
    }
    
    func markActiveTabAsRead(_ tab:String) {
        switch tab {
        case "Mentions":
            nvm.markMentionsAsRead()
        case "Reactions":
            nvm.markReactionsAsRead()
        case "Reposts":
            nvm.markRepostsAsRead()
        case "Zaps":
            nvm.markZapsAsRead()
        case "Followers":
            nvm.markNewFollowersAsRead()
        default:
            break
        }
    }
}

struct NotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.loadRepliesAndReactions()
            pe.loadZaps()
        }) {
            NotificationsContainer()
        }
    }
}
