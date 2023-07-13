//
//  NotificationsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/02/2023.
//

import SwiftUI
import CoreData

struct NotificationsContainer: View {
    @StateObject private var nm:NotificationsManager = .shared
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    @AppStorage("selected_tab") var selectedTab = "Main"
    @State var navPath = NavigationPath()
    
    var body: some View {
//        let _ = Self._printChanges()
        NavigationStack(path: $navPath) {
            VStack {
                if let account = ns.account {
                    NotificationsView(account: account)
                }
                else {
                    Text("Select account account first")
                }
            }
            .withNavigationDestinations()
        }
        .onReceive(receiveNotification(.navigateTo)) { notification in
            let destination = notification.object as! NavigationDestination
            guard !IS_IPAD else { return }
            guard selectedTab == "Notifications" else { return }
            navPath.append(destination.destination)
        }
        .onReceive(receiveNotification(.clearNavigation)) { notification in
            navPath.removeLast(navPath.count)
        }
    }
}

struct NotificationsView: View {
    @Environment(\.managedObjectContext) var viewContext
    @ObservedObject var nm:NotificationsManager = .shared
    @ObservedObject var account:Account
    let sp:SocketPool = .shared
    
    @State var tab = "Posts"
    @ObservedObject var settings:SettingsStore = .shared
    @State var markAsReadDelayer:Timer?
    
    var body: some View {
//        let _ = Self._printChanges()
        VStack(spacing:0) {
            HStack {
                TabButton(action: {
                    withAnimation {
                        tab = "Posts"
//                        nm.unreadMentions = 0
                    }
                }, title: String(localized: "Posts", comment:"Title of tab"), selected: tab == "Posts", unread: nm.unreadMentions)
                
                TabButton(action: {
                    withAnimation {
                        tab = "Reactions"
//                        nm.unreadReactions = 0
                    }
                }, title: String(localized: "Reactions", comment:"Title of tab"), selected: tab == "Reactions", unread: nm.unreadReactions)
                
                TabButton(action: {
                    withAnimation {
                        tab = "Zaps"
//                        nm.unreadZaps = 0
                    }
                }, title: String(localized: "Zaps", comment:"Title of tab"), selected: tab == "Zaps", unread: nm.unreadZaps)
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
            markActiveTabAsRead()
        }
        .onChange(of: tab, perform: { newValue in
            markActiveTabAsRead()
        })
        .overlay(alignment: .bottom) {
            if settings.statusBubble {
                ProcessingStatus()
                    .opacity(0.85)
                    .padding(.bottom, 10)
            }
        }
        .padding(.top, 5)
        .navigationTitle(tab)
        .navigationBarHidden(true)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    func markActiveTabAsRead() {
        markAsReadDelayer?.invalidate()
        
        markAsReadDelayer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            // Mark unread for active tab
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
