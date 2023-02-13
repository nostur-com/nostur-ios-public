//
//  NotificationsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/02/2023.
//

import SwiftUI

struct NotificationsView: View {
    
    @AppStorage("lastNotificationDate") var lastNotificationDate = 0
    
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var sp:SocketPool
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        predicate: NSPredicate(format: "kind IN {1,7,9735}")
    )
    var events:FetchedResults<Event>
    
    @State var tab = "NOTES"
    
    var myNotifications:[Event] {
        get {
            events.filter { ($0.kind == 1) && ($0.tags() ?? []).contains(where: { $0.pubkey == ns.activeAccountPublicKey })}
        }
    }
    
    var myReactions:[Event] {
        get {
            events.filter { ($0.kind == 7) && ($0.tags() ?? []).contains(where: { $0.pubkey == ns.activeAccountPublicKey })}
        }
    }
    
    var myZaps:[Event] {
        get {
            events.filter { ($0.kind == 9735) }
        }
    }
    
    var body: some View {
        VStack {
            if let account = ns.account {
                Text("account: \(account.name)")
                TabView(selection: $tab) {
                    Notes(notes: myNotifications) { creationDate in
                        lastNotificationDate = creationDate
                    }
                    .tabItem { Text("Notes") }
                    
                    Reactions(reactions: myReactions) { creationDate in
                        lastNotificationDate = creationDate
                    }
                    .tabItem  { Text("Reactions") }
                    
                    Zaps(zaps: myZaps) { creationDate in
                        lastNotificationDate = creationDate
                    }
                    .tabItem  { Text("Zaps") }
                }
                .onAppear {
                    fetchMentions()
                }
                Spacer()
            }
            else {
                Text("No active account")
            }
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
            List {
                ForEach(notes) { event in
                    NoteRowView(event: event)
                        .listRowInsets(EdgeInsets())
                        .onAppear {
                            onAppear(Int(event.created_at))
                        }
                }
            }.listStyle(.plain)
        }
    }
    
    struct Reactions: View {
        var reactions:[Event]
        var onAppear:(Int) -> ()
        
        var body: some View {
            List {
                ForEach(reactions) { event in
                    NoteRowView(event: event)
                        .listRowInsets(EdgeInsets())
                        .onAppear {
                            onAppear(Int(event.created_at))
                        }
                }
            }.listStyle(.plain)
        }
    }
    
    struct Zaps: View {
        var zaps:[Event]
        var onAppear:(Int) -> ()
        
        var body: some View {
            List {
                ForEach(zaps) { event in
                    NoteRowView(event: event)
                        .listRowInsets(EdgeInsets())
                        .onAppear {
                            onAppear(Int(event.created_at))
                        }
                }
            }.listStyle(.plain)
        }
    }
}

struct NotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationsView()
            .withPreviewEnvironment()
    }
}
