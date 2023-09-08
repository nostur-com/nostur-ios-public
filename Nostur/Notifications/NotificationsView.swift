//
//  NotificationsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/02/2023.
//

import SwiftUI
import CoreData

struct NotificationsContainer: View {
    @EnvironmentObject var theme: Theme
    @StateObject private var nm:NotificationsManager = .shared
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    @AppStorage("selected_tab") var selectedTab = "Main"
    @AppStorage("selected_notifications_tab") var selectedNotificationsTab = "Posts"
    @State var navPath = NavigationPath()
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
//    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    var body: some View {
//        let _ = Self._printChanges()
        NavigationStack(path: $navPath) {
            VStack {
                if let account = ns.account {
                    NotificationsView(account: account, tab: $selectedNotificationsTab)
                }
                else {
                    Text("Select account account first")
                }
            }
            .background(theme.listBackground)
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
    @EnvironmentObject var theme:Theme
    @Environment(\.managedObjectContext) var viewContext
    @ObservedObject var nm:NotificationsManager = .shared
    @ObservedObject var account:Account
    let sp:SocketPool = .shared
    
    @Binding var tab:String
    @ObservedObject var settings:SettingsStore = .shared
    @State var markAsReadDelayer:Timer?
    @State var showNotificationSettings = false
    @AppStorage("notifications_mute_reactions") var muteReactions:Bool = false
    @AppStorage("notifications_mute_zaps") var muteZaps:Bool = false
    
    var body: some View {
//        let _ = Self._printChanges()
        VStack(spacing:0) {
            HStack {
                TabButton(action: {
                    withAnimation {
                        tab = "Posts"
                        nm.unreadMentions = 0
                    }
                }, title: String(localized: "Posts", comment:"Title of tab"), selected: tab == "Posts", unread: nm.unreadMentions)
                
                TabButton(action: {
                    withAnimation {
                        tab = "Reactions"
                        nm.unreadReactions = 0
                    }
                }, title: String(localized: "Reactions", comment:"Title of tab"), selected: tab == "Reactions", unread: nm.unreadReactions, muted: muteReactions)
                
                TabButton(action: {
                    withAnimation {
                        tab = "Zaps"
                        nm.unreadZaps = 0
                    }
                }, title: String(localized: "Zaps", comment:"Title of tab"), selected: tab == "Zaps", unread: nm.unreadZaps, muted: muteZaps)
            }
            
            switch (tab) {
                case "Posts":
                    NotificationsPosts(pubkey: account.publicKey)
                case "Reactions":
                    NotificationsReactions()
                case "Zaps":
                    NotificationsZaps(pubkey: account.publicKey)
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
                    .foregroundColor(theme.accent)
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
        if tab == "Posts" {
            NotificationsManager.shared.markMentionsAsRead()
        }
        else if tab == "Reactions" {
            NotificationsManager.shared.markReactionsAsRead()
        }
        else {
            NotificationsManager.shared.markZapsAsRead()
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
