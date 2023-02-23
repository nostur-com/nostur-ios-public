//
//  NotificationsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/02/2023.
//

import SwiftUI
import CoreData

struct NotificationsView: View {
    
    @AppStorage("lastNotificationDate") var lastNotificationDate = 0
    
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var sp:SocketPool
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        predicate: NSPredicate(value: false)
    )
    var kind1:FetchedResults<Event>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        predicate: NSPredicate(value: false)
    )
    var kind7:FetchedResults<Event>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        predicate: NSPredicate(value: false)
    )
    var kind9735:FetchedResults<Event>
    
    @State var tab = "REACTIONS"
    
    init() {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(value: false)
        fr.fetchLimit = 125 // 5 = FAST TIMELINE TO DETAIL. 75 = SLOW (MET VSTACK).
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _kind1 = FetchRequest(fetchRequest: fr)
        
        let kind7r:NSFetchRequest<Event> = Event.fetchRequest()
        kind7r.fetchLimit = 100
        kind7r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        kind7r.predicate = NSPredicate(value: false)
        _kind7 = FetchRequest(fetchRequest: kind7r)
        
        let kind9735r:NSFetchRequest<Event> = Event.fetchRequest()
        kind9735r.fetchLimit = 100
        kind9735r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        kind9735r.predicate = NSPredicate(value: false)
        _kind9735 = FetchRequest(fetchRequest: kind9735r)
    }
    
    var myNotifications:[Event] {
        get {
            kind1.filter { ($0.tags() ?? []).filter { $0.pubkey == ns.account!.publicKey! }.count > 0 }
        }
    }
    
    var myReactions:[Event] {
        get {
            kind7.filter { ($0.tags() ?? []).filter { $0.pubkey == ns.account!.publicKey! }.count > 0 }
        }
    }
    
    var myZaps:[Event] {
        get {
            kind9735.filter { ($0.tags() ?? []).filter { $0.pubkey == ns.account!.publicKey! }.count > 0 }
        }
    }
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
            if let account = ns.account {
                Text("account: \(account.name)")
                // TODO: MAKE TAB STYLE
                HStack {
                    Button { tab = "NOTES" } label: { Text("Posts") }
                    Button { tab = "REACTIONS" } label: { Text("Reactions") }
                    Button { tab = "ZAPS" } label: { Text("Zaps") }
                }
                .buttonStyle(.bordered)
                
                switch (tab) {
                    case "NOTES":
                        Notes(notes: myNotifications) { creationDate in
                            lastNotificationDate = creationDate
                        }
                    case "REACTIONS":
                        Reactions(reactions: myReactions) { creationDate in
                            lastNotificationDate = creationDate
                        }
                    case "ZAPS":
                        Zaps(zaps: myZaps) { creationDate in
                            lastNotificationDate = creationDate
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
            kind1.nsPredicate = NSPredicate(format: "kind == 1 AND tagsSerialized CONTAINS %@", ns.account!.publicKey!)
            
            kind7.nsPredicate = NSPredicate(format: "kind == 7 AND tagsSerialized CONTAINS %@", ns.account!.publicKey!)
            
            kind9735.nsPredicate = NSPredicate(format: "kind == 9735 AND tagsSerialized CONTAINS %@", ns.account!.publicKey!)

            fetchMentions()
        }
    }
    
    func fetchMentions() {
        sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getMentions(pubkeys: [ns.activeAccountPublicKey], since: lastNotificationDate != 0 ? NTimestamp(timestamp: lastNotificationDate) : nil)))
    }
}

extension NotificationsView {
    struct Notes: View {
        var notes:[Event]
        var onAppear:(Int) -> ()
        
        var body: some View {
            let _ = Self._printChanges()
            ScrollView {
                LazyVStack {
                    ForEach(notes) { event in
                        NoteRowView(event: event)
                            .onAppear {
                                onAppear(Int(event.created_at))
                            }
                    }
                }
            }
        }
    }
    
    struct Reactions: View {
        var reactions:[Event]
        var onAppear:(Int) -> ()
        
        var body: some View {
            let _ = Self._printChanges()
            ScrollView {
                LazyVStack {
                    ForEach(reactions) { event in
                        NoteRowView(event: event)
                            .onAppear {
                                onAppear(Int(event.created_at))
                            }
                    }
                }
            }
        }
    }
    
    struct Zaps: View {
        var zaps:[Event]
        var onAppear:(Int) -> ()
        
        var body: some View {
            let _ = Self._printChanges()
            ScrollView {
                LazyVStack {
                    ForEach(zaps) { event in
                        ZapRow(event: event)
                            .onAppear {
                                onAppear(Int(event.created_at))
                            }
                    }
                }
            }
        }
    }
}

struct NotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationsView()
            .withPreviewEnvironment()
    }
}
