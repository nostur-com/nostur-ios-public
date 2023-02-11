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
        predicate: NSPredicate(format: "kind == 1")
    )
    var events:FetchedResults<Event>
    
    var myNotifications:[Event] {
        get {
            events.filter { ($0.tags() ?? []).contains(where: { $0.pubkey == ns.activeAccountPublicKey })}
        }
    }
    
    var body: some View {
        VStack {
            if let account = ns.account {
                Text("account: \(account.name)")
                List {
                    ForEach(myNotifications) { event in
                        NoteRowView(event: event)
                            .listRowInsets(EdgeInsets())
                            .onAppear {
                                lastNotificationDate = Int(event.created_at)
                            }
                    }
                }
                .listStyle(.plain)
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

struct NotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationsView()
            .withPreviewEnvironment()
    }
}
