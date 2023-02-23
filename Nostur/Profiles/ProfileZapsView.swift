//
//  ProfileZapsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 18/02/2023.
//

import SwiftUI

// NOTES ON USER PROFILE SCREEN
struct ProfileZapsView: View {
    
//    @EnvironmentObject var cm:ConnectionManager
    var sp:SocketPool = .shared
    var pubkey:String
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Event.created_at, order: .reverse)],
        predicate: NSPredicate(format: "kind IN {9735}"),
        animation: .none)
    var events: FetchedResults<Event> // ZAP EVENTS FROM CUSTODIAL PROVIDER
    var events_:[Event] { Array(events) } // ZAP EVENTS FROM CUSTODIAL PROVIDER
    
    init(pubkey: String) {
        self.pubkey = pubkey
        _events = FetchRequest(
            sortDescriptors: [SortDescriptor(\Event.created_at, order: .reverse)],
            predicate: NSPredicate(format: "kind = 9735 AND tagsSerialized CONTAINS %@", "[\"p\",\"\(pubkey)") // OPTIMIZATION HACK
        )
    }
    
    
    var body: some View {
        
        VStack {
            if (events.count == 0) {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(50)
                    Spacer()
                }
            }
            else {
                LazyVStack {
                    ForEach(events, id:\Event.id) { event in
//                        NoteRowView(event:event)
                        ZapRow(event: event)
                        Divider()
                    }
                }
            }
        }
        .onAppear {
            print("🟢 ProfileZapsView.onAppear always REQ.9735 \(pubkey)")
            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorZaps(pubkey: pubkey)))
        }
        .onChange(of: events_) { newZapEvents in
            var missingContacts:[String] = []
            var missingEvents:[String] = []
            
            for event in newZapEvents {
                if (event.zapFromRequest == nil) { print("🔴🔴 wheres the zap request bro. event.id: \(event.id!)");continue }
                if (event.zapFromRequest?.contact == nil || event.zapFromRequest?.contact?.updated_at == 0) {
                    missingContacts.append(event.zapFromRequest!.pubkey!)
                }
                if (event.zappedEventId != nil && event.zappedEvent == nil) {
                    if (event.zapFromRequest?.zappedEvent == nil) {
                        missingEvents.append(event.zappedEventId!)
                    }
                }
            }
            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: missingContacts)))
            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvents(ids: missingEvents)))
            if (missingContacts.count > 0  || missingEvents.count > 0) {
                print("🟣 Fetching \(missingContacts.count) missing contacts, and \(missingEvents.count ) missing events that received zaps")
            }
        }
        
    }
}

struct ProfileZapsView_Previews: PreviewProvider {
    static var previews: some View {
        
        // snowden: 84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240
        
        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
        
        ScrollView {
            ProfileZapsView(pubkey: pubkey)
                .withPreviewEnvironment()
        }
    }
}
