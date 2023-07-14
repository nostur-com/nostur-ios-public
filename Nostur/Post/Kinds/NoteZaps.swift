//
//  NoteZaps.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/02/2023.
//

import SwiftUI

struct NoteZaps: View {
    let sp:SocketPool = .shared
    let id:String
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)], predicate: NSPredicate(value: false))
    var zaps:FetchedResults<Event>
    var zapsSorted:[Event] { zaps.sorted(by: { $0.naiveSats > $1.naiveSats }).uniqued(on: { $0.id }) }
    
    var unverifiedZaps:[Event] {
        zapsSorted.filter { $0.flags != "zpk_verified" }
    }
    
    init(id:String) {
        self.id = id
        _zaps = FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)], predicate: NSPredicate(format: "zappedEventId == %@ AND kind == 9735", id))
    }
    
    var body: some View {
        ScrollView {
            
            LazyVStack(alignment: .leading) {
                ForEach(zapsSorted.filter { $0.flags == "zpk_verified" } ) { zap in
                    if let zapFrom = zap.zapFromRequest {
                        NoteZapRow(zap: zap, zapFrom:zapFrom)
                    }
                }
                
                if !unverifiedZaps.isEmpty {
                    Text("Unverified zaps", comment: "List of unverified zaps")
                        .fontWeight(.bold)
                        .padding(10)
                    
                    ForEach(unverifiedZaps) { zap in
                        if let zapFrom = zap.zapFromRequest {
                            NoteZapRow(zap: zap, zapFrom:zapFrom)
                        }
                    }
                }
            }
            
            
            Spacer()
        }
        .task {
            // Fix zaps afterwards??
            // (0, 0) = (tally, count)
            let tally = zaps
                .filter { $0.flags == "zpk_verified" }
                .reduce((0, 0)) { partialResult, zap in
                return (partialResult.0 + Int64(zap.naiveSats), partialResult.1 + Int64(1))
            }
            if let event = try? DataProvider.shared().fetchEvent(id: id) {
                if event.zapsCount != tally.1 {
                    event.objectWillChange.send()
                    event.zapsCount = tally.1
                    event.zapTally = tally.0
                }
            }
            
            var missing:[Event] = []
            for zap in zaps {
                if let zapFrom = zap.zapFromRequest {
                    if let contact = zapFrom.contact, contact.metadata_created_at == 0 {
                        missing.append(zapFrom)
                        EventRelationsQueue.shared.addAwaitingContact(contact, debugInfo: "NoteZaps.001")
                    }
                    else if zapFrom.contact == nil {
                        missing.append(zapFrom)
                        EventRelationsQueue.shared.addAwaitingEvent(zapFrom, debugInfo: "NoteZaps.002")
                    }
                    if zapFrom.contact == nil || zapFrom.contact?.metadata_created_at == 0 {
                        
                    }
                }
            }
            
            QueuedFetcher.shared.enqueue(pTags: missing.map { $0.pubkey })
        }
    }
}

struct NoteZapRow: View {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    let er:ExchangeRateModel = .shared
     
    @AppStorage("devToggle") var devToggle:Bool = false
    
    // THE ZAP EVENT (FROM CUSTODIAL ZAP PROVIDER)
    var zap:Event
    @ObservedObject var zapFrom:Event
    
    var fiatPrice:String {
        get {
            String(format: "($%.02f)",(Double(zap.naiveSats / 100000000 * er.bitcoinPrice)))
        }
    }
    
    var body: some View {
        
        HStack(alignment: .top) {
            PFP(pubkey: zapFrom.pubkey, contact: zapFrom.contact)
                .onTapGesture {
                    navigateTo(ContactPath(key: zapFrom.pubkey))
                }
            VStack(alignment: .leading) {
                NoteHeaderViewEvent(event: zapFrom)
                Text("Zapped \(zap.naiveSats.satsFormatted) sats \(fiatPrice)", comment: "Text showing how many sats someone zapped, followed by fiat price")
                Text(zapFrom.content ?? "")
//                Text(zap.flags)
//                Text("expected zpk: \(zap.zappedContact?.zapperPubkey ?? "?") - zap.pubkey: \(zap.pubkey)")
            }
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture {
            navigateTo(ContactPath(key: zapFrom.pubkey))
        }
        Divider()
    }
}

struct NoteZaps_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadZaps()
        }) {
            VStack {
                
                if let dunno1 = PreviewFetcher.fetchEvent("81b2dba2a3d2c92eedab1f966119bda65555d926b97bb41a14c07187472f6159") {
                    NoteZaps(id: dunno1.id)
                }
                
                if let dunno = PreviewFetcher.fetchEvent("7682031bb0b06d7b9c417dae30141357a74b4f089ebd46226990d418e2def565") {
                    NoteZaps(id: dunno.id)
                }
            }
        }
    }
}
