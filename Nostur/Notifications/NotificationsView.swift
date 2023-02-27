//
//  NotificationsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/02/2023.
//

import SwiftUI
import CoreData

struct NotificationsW: View {
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
    
    @FetchRequest
    var kind1:FetchedResults<Event>
    
    @State var tab = "NOTES"
    
    init(account:Account) {
        self.account = account
        print("🧨🧨🧨🧨🧨 INIT NOTIFICATIONS VIEW 🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 1 AND tagsSerialized CONTAINS %@", account.publicKey)
        fr.fetchLimit = 125 // 5 = FAST TIMELINE TO DETAIL. 75 = SLOW (MET VSTACK).
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _kind1 = FetchRequest(fetchRequest: fr)
    }
    
    var myNotifications:[Event] {
        get {
            kind1.filter { $0.tags().filter { $0.pubkey == account.publicKey }.count > 0 }
        }
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
                        Notes(notes: myNotifications) { creationDate in
                            if (creationDate > account.lastNotificationDate) {
                                account.lastNotificationDate = creationDate
                            }
                        }
                    case "REACTIONS":
                        NotificationsV(pubkey: ns.account!.publicKey, context: viewContext) { creationDate in
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
        .onAppear {
            guard ns.account != nil else { return }
            kind1.nsPredicate = NSPredicate(format: "kind == 1 AND tagsSerialized CONTAINS %@", account.publicKey)
            fetchMentions()
        }
    }
    
    func fetchMentions() {
        guard ns.account != nil else { return }
        sp.sendMessage(
            ClientMessage(type: .REQ,
                          message:
                            RequestMessage.getMentions(
                                pubkeys: [ns.account!.publicKey],
                                kinds: [1],
                                limit: 500,
                                since: NTimestamp(timestamp: Int(myNotifications.first?.created_at ?? 0)))
                         )
        )
    }
}

extension NotificationsView {
    struct Notes: View {
        var notes:[Event]
        var onAppear:(Int64) -> ()
        
        var body: some View {
            let _ = Self._printChanges()
            ScrollView {
                LazyVStack {
                    ForEach(notes) { event in
                        NoteRowView(event: event)
                            .onAppear {
                                onAppear(event.created_at)
                            }
                        Divider()
                    }
                }
            }
        }
    }
    
    struct Reactions: View {
        var reactions:[Event]
        var onAppear:(Int64) -> ()
        
        var body: some View {
            let _ = Self._printChanges()
            ScrollView {
                LazyVStack {
                    ForEach(reactions) { event in
                        NoteRowView(event: event)
                            .onAppear {
                                onAppear(event.created_at)
                            }
                    }
                }
            }
        }
    }
    
    struct Zaps: View {
        var zaps:[Event]
        var onAppear:(Int64) -> ()
        
        var body: some View {
            let _ = Self._printChanges()
            ScrollView {
                LazyVStack {
                    ForEach(zaps) { event in
                        ZapRow(event: event)
                            .onAppear {
                                onAppear(event.created_at)
                            }
                    }
                }
            }
        }
    }
}

struct NotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationsW()
            .withPreviewEnvironment()
    }
}
