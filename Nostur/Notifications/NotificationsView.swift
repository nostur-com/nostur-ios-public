//
//  NotificationsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/02/2023.
//

import SwiftUI
import CoreData

struct NotificationsContainer: View {
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    @AppStorage("selected_tab") var selectedTab = "Main"
    @State var navPath = NavigationPath()
    
    var body: some View {
        let _ = Self._printChanges()
        NavigationStack(path: $navPath) {
            VStack {
                if (ns.account != nil) {
                    NotificationsView(account: ns.account!)
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
    @EnvironmentObject var ns:NosturState
    let sp:SocketPool = .shared
    
    @State var tab = "Posts"
    
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
            if let account = ns.account {
                HStack {
                    TabButton(action: {
                        withAnimation {
                            tab = "Posts"
                            nm.unreadMentions = 0
                        }
                    }, title: "Posts", selected: tab == "Posts", unread: nm.unreadMentions)
                    
                    TabButton(action: {
                        withAnimation {
                            tab = "Reactions"
                            nm.unreadReactions = 0
                        }
                    }, title: "Reactions", selected: tab == "Reactions", unread: nm.unreadReactions)
                    
                    TabButton(action: {
                        withAnimation {
                            tab = "Zaps"
                            nm.unreadZaps = 0
                        }
                    }, title: "Zaps", selected: tab == "Zaps", unread: nm.unreadZaps)
                }
                
                switch (tab) {
                    case "Posts":
                        NotificationsPosts(pubkey: account.publicKey, mutedRootIds: account.mutedRootIds_, blockedPubkeys: account.blockedPubkeys_, context: viewContext)
                            .equatable()
//                            .padding(.horizontal, 10)
                    case "Reactions":
                        NotificationsReactions(pubkey: account.publicKey, blockedPubkeys: account.blockedPubkeys_, context: viewContext)
                            .equatable()
                            .padding(.horizontal, 10)
                    case "Zaps":
                        NotificationsZaps(pubkey: account.publicKey, blockedPubkeys: account.blockedPubkeys_, context: viewContext)
                            .equatable()
//                            .padding(.horizontal, 10)
                    default:
                        EmptyView()
                }
                Spacer()
            }
            else {
                Text("No active account")
            }
        }
        .overlay(alignment: .bottom) {
            ProcessingStatus()
                .opacity(0.85)
                .padding(.bottom, 10)
        }
        .padding(.top, 5)
        .navigationTitle(tab)
        .navigationBarHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if tab == "Posts" {
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(3)) {
                    self.nm.unreadMentions = 0
                }
            }
        }
    }
}

struct NotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationsContainer()
            .withPreviewEnvironment()
    }
}
