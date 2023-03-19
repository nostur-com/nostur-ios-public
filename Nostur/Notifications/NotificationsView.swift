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
        let _ = print("🧨🧨🧨🧨🧨 BODY NOTIFICATIONS CONTAINER 🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
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
    
    @ObservedObject var account:Account
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var sp:SocketPool
    
    @State var tab = "Posts"
    
    
    var body: some View {
        let _ = print("🧨🧨🧨🧨🧨  NOTIFICATIONS VIEW 🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
        let _ = Self._printChanges()
        VStack {
            if let account = ns.account {
                HStack {
                    TabButton(action: {
                        withAnimation {
                            tab = "Posts"
                        }
                    }, title: "Posts", selected: tab == "Posts")
                    
                    TabButton(action: {
                        withAnimation {
                            tab = "Reactions"
                        }
                    }, title: "Reactions", selected: tab == "Reactions")
                    
                    TabButton(action: {
                        withAnimation {
                            tab = "Zaps"
                        }
                    }, title: "Zaps", selected: tab == "Zaps")
                }
                
                switch (tab) {
                    case "Posts":
                        NotificationsNotes(pubkey: ns.account!.publicKey, mutedRootIds: ns.account?.mutedRootIds_ ?? [], blockedPubkeys: ns.account?.blockedPubkeys_ ?? [], context: viewContext) { creationDate in
                            if (creationDate > account.lastNotificationDate) {
                                account.lastNotificationDate = creationDate
                            }
                        }
                    case "Reactions":
                        NotificationsReactions(pubkey: ns.account!.publicKey, blockedPubkeys: ns.account?.blockedPubkeys_ ?? [], context: viewContext) { creationDate in
                            if (creationDate > account.lastNotificationDate) {
                                account.lastNotificationDate = creationDate
                            }
                        }
                    case "Zaps":
                        NotificationsZaps(pubkey: ns.account!.publicKey, context: viewContext) { creationDate in
                            if (creationDate > account.lastNotificationDate) {
                                account.lastNotificationDate = creationDate
                            }
                        }
                    default:
                        EmptyView()
                }
                Spacer()
            }
            else {
                Text("No active account")
            }
        }
        .navigationTitle(tab)
        .navigationBarHidden(true)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationsContainer()
            .withPreviewEnvironment()
    }
}
