//
//  NotificationsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/02/2023.
//

import SwiftUI
import CoreData
import NavigationBackport

struct NotificationsContainer: View {
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject var la: LoggedInAccount

    // Not observed so manual UserDefaults
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Notifications" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    @State private var navPath = NBNavigationPath()
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        NBNavigationStack(path: $navPath) {
            VStack {
                NotificationsView(account: la.account, navPath: $navPath)
            }
            .background(themes.theme.listBackground)
            .withNavigationDestinations()
        }
        .nbUseNavigationStack(.never)
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
    @ObservedObject public var account:CloudAccount
    
    @AppStorage("selected_notifications_tab") private var tab = "Mentions"

    @Binding public var navPath: NBNavigationPath
    
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
                    }, icon: "text.bubble", selected: tab == "Mentions", unread: nvm.unreadMentions)
                    
                    TabButton(action: {
                        withAnimation {
                            tab = "New Posts"
                            nvm.markNewPostsAsRead()
                        }
                    }, icon: "bell", selected: tab == "New Posts", unread: nvm.unreadNewPosts)
                    
                    TabButton(action: {
                        withAnimation {
                            tab = "Reactions"
                            nvm.markReactionsAsRead()
                        }
                    }, icon: "heart", selected: tab == "Reactions", unread: nvm.unreadReactions_, muted: nvm.muteReactions)
                    
                    TabButton(action: {
                        withAnimation {
                            tab = "Reposts"
                            nvm.markRepostsAsRead()
                        }
                    }, icon: "arrow.2.squarepath", selected: tab == "Reposts", unread: nvm.unreadReposts_, muted: nvm.muteReposts)
                    
                    TabButton(action: {
                        withAnimation {
                            tab = "Zaps"
                            nvm.markZapsAsRead()
                        }
                    }, icon: "bolt", selected: tab == "Zaps", unread: nvm.muteZaps ? nvm.unreadFailedZaps_ : (nvm.unreadZaps_ + nvm.unreadFailedZaps_), muted: nvm.muteZaps)
                    
                    TabButton(action: {
                        withAnimation {
                            tab = "Followers"
                            nvm.markNewFollowersAsRead()
                        }
                    }, icon: "person.3", selected: tab == "Followers", unread: nvm.unreadNewFollowers_, muted: nvm.muteFollows)
                }
//                .padding(.horizontal, 10)
                .frame(minWidth: dim.listWidth)
            }
            .frame(width: dim.listWidth)
            
            switch (tab) {
                case "Mentions", "Posts": // (old name was "Posts")
                    NotificationsMentions(navPath: $navPath)   
                case "New Posts":
                    NotificationsNewPosts(pubkey: account.publicKey, navPath: $navPath)
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
        .sheet(isPresented: $showNotificationSettings, content: {
            NBNavigationStack {
                NotificationSettings()
            }
            .nbUseNavigationStack(.never)
        })
    }
    
    func markActiveTabAsRead(_ tab:String) {
        switch tab {
        case "Mentions":
            nvm.markMentionsAsRead()   
        case "New Posts":
            nvm.markNewPostsAsRead()
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
