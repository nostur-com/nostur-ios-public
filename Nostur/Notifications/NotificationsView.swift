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
    
    var body: some View {
        let _ = Self._printChanges()
        if (ns.account != nil) {
            NotificationsView(account: ns.account!)
        }
        else {
            Text("Select account account first")
        }
    }
}

struct NotificationsView: View {
    @Environment(\.managedObjectContext) var viewContext
    
    @ObservedObject var account:Account
    
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var sp:SocketPool
    
    @State var tab = "NOTES"
    
    init(account:Account) {
        self.account = account
        print("🧨🧨🧨🧨🧨 INIT NOTIFICATIONS VIEW 🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
    }
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
            if let account = ns.account {
                HStack {
                    TabButton(action: {
                        withAnimation {
                            tab = "NOTES"
                        }
                    }, title: "Posts", selected: tab == "NOTES")
                    
                    TabButton(action: {
                        withAnimation {
                            tab = "REACTIONS"
                        }
                    }, title: "Reactions", selected: tab == "REACTIONS")
                    
                    TabButton(action: {
                        withAnimation {
                            tab = "ZAPS"
                        }
                    }, title: "Zaps", selected: tab == "ZAPS")
                }
                
                switch (tab) {
                    case "NOTES":
                        NotificationsNotes(pubkey: ns.account!.publicKey, mutedRootIds: ns.account?.mutedRootIds_ ?? [], context: viewContext) { creationDate in
                            if (creationDate > account.lastNotificationDate) {
                                account.lastNotificationDate = creationDate
                            }
                        }
                    case "REACTIONS":
                        NotificationsReactions(pubkey: ns.account!.publicKey, context: viewContext) { creationDate in
                            if (creationDate > account.lastNotificationDate) {
                                account.lastNotificationDate = creationDate
                            }
                        }
                    case "ZAPS":
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
    }
}

struct NotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationsContainer()
            .withPreviewEnvironment()
    }
}
