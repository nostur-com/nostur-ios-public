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
    @EnvironmentObject var nav:NavigationModel
    
    var body: some View {
        let _ = Self._printChanges()
        NavigationStack(path: $nav.notificationsPath) {
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
    }
}

struct NotificationsView: View {
    @Environment(\.managedObjectContext) var viewContext
    @ObservedObject var nm:NotificationsManager = .shared
    @ObservedObject var account:Account
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var sp:SocketPool
    
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
                        NotificationsPosts(pubkey: account.publicKey, mutedRootIds: account.mutedRootIds_, blockedPubkeys: account.blockedPubkeys_, context: viewContext, onAppear: saveLastSeenPost)
                            .equatable()
                            .padding(.horizontal, 10)
                    case "Reactions":
                        NotificationsReactions(pubkey: account.publicKey, blockedPubkeys: account.blockedPubkeys_, context: viewContext, onAppear: saveLastSeenReaction)
                            .equatable()
                            .padding(.horizontal, 10)
                    case "Zaps":
                        NotificationsZaps(pubkey: account.publicKey, blockedPubkeys: account.blockedPubkeys_, context: viewContext, onAppear: saveLastSeenZap)
                            .equatable()
                            .padding(.horizontal, 10)
                    default:
                        EmptyView()
                }
                Spacer()
            }
            else {
                Text("No active account")
            }
        }
        .padding(.top, 5)
        .navigationTitle(tab)
        .navigationBarHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            nm.unreadMentions = 0
        }
    }
    
    func saveLastSeenPost(_ insertedAt:Date) {
//        if (insertedAt > lst.lastSeenPostInsertedAt ?? Date.init(timeIntervalSince1970: 0)) {
//            lst.lastSeenPostInsertedAt = insertedAt
//            nm.saveContext.send()
//        }
    }
    
    func saveLastSeenReaction(_ insertedAt:Date) {
//        if (insertedAt > lst.lastSeenReactionInsertedAt ?? Date.init(timeIntervalSince1970: 0)) {
//            lst.lastSeenReactionInsertedAt = insertedAt
//            nm.saveContext.send()
//        }
    }
    
    func saveLastSeenZap(_ insertedAt:Date) {
//        if (insertedAt > lst.lastSeenZapInsertedAt ?? Date.init(timeIntervalSince1970: 0)) {
//            lst.lastSeenZapInsertedAt = insertedAt
//            nm.saveContext.send()
//        }
    }
}

struct NotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationsContainer()
            .withPreviewEnvironment()
    }
}
