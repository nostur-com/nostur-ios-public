//
//  NoteZaps.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/02/2023.
//

import SwiftUI
//import LightningDevKit


struct NoteZaps: View {
//    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var sp:SocketPool
    @ObservedObject var event:Event
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)], predicate: NSPredicate(value: false))
    var zaps:FetchedResults<Event>
    var zapsSorted:[Event] { zaps.sorted(by: { $0.naiveSats > $1.naiveSats }) }
    
    init(event:Event) {
        self.event = event
        _zaps = FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)], predicate: NSPredicate(format: "zappedEventId == %@ AND kind == 9735", event.id))
    }
    
    var body: some View {
        ScrollView {
            ForEach(zapsSorted) { zap in
                NoteZapRow(event: zap)
            }
            Spacer()
        }
        .task {
            // Fix zaps afterwards??
            let tally = zaps.reduce((0, 0)) { partialResult, zap in
                return (partialResult.0 + Int64(zap.naiveSats), partialResult.1 + Int64(1))
            }
            if event.zapsCount != tally.1 {
                event.objectWillChange.send()
                event.zapsCount = tally.1
                event.zapTally = tally.0
            }
            
        }
    }
}

struct NoteZapRow: View {
    @Environment(\.managedObjectContext) var viewContext
    let er:ExchangeRateModel = .shared
     
    @AppStorage("devToggle") var devToggle:Bool = false
    
    // THE ZAP EVENT (FROM CUSTODIAL ZAP PROVIDER)
    var event:Event
    
    var fiatPrice:String {
        get {
            String(format: "($%.02f)",(Double(event.naiveSats / 100000000 * er.bitcoinPrice)))
        }
    }
    
    var body: some View {
        
        HStack(alignment: .top) {
            PFP(pubkey: event.zapFromRequest?.pubkey ?? "WTF", pictureUrl: event.zapFromRequest?.contact?.picture)
                .onTapGesture {
                    if let pubkey = event.zapFromRequest?.pubkey {
                        navigateTo(ContactPath(key: pubkey))
                    }
                }
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {
                        HStack(spacing:3) {
                            Text(event.zapFromRequest?.contact?.authorName ?? "").font(.headline).foregroundColor(.primary)
                                .lineLimit(1)

                            if (event.zapFromRequest?.contact?.nip05veried ?? false) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color("AccentColor"))
                            }

                            Group {
                                Text("@\(event.zapFromRequest?.contact?.username ?? event.zapFromRequest?.authorKey ?? "?")").layoutPriority(1)
                                Text(" · ") //
                                Ago(event.date).layoutPriority(1) //
                            }
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        }
                    }.multilineTextAlignment(.leading)
                    Spacer()

                }
                Text("Zapped \(event.naiveSats.clean) sats \(fiatPrice)")
                Text(event.zapFromRequest?.content ?? "")
            }
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture {
            if (event.zapFromRequest != nil) {
                navigateTo(ContactPath(key: event.zapFromRequest!.pubkey))
            }
        }
        Divider()
    }
}

struct NoteZaps_Previews: PreviewProvider {
    static var previews: some View {
        // Some fake and real Zaps
        
        let odell = PreviewFetcher.fetchEvent("81b2dba2a3d2c92eedab1f966119bda65555d926b97bb41a14c07187472f6159")
        
        let dunno = PreviewFetcher.fetchEvent("7682031bb0b06d7b9c417dae30141357a74b4f089ebd46226990d418e2def565")
        
        VStack {
            
            if dunno != nil {
                NoteZaps(event: dunno!)
            }
            
            if (odell != nil) {
                NoteZaps(event: odell!)
            }
        }
        .withPreviewEnvironment()
        
    
    }
}
