//
//  NoteZaps.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/02/2023.
//

import SwiftUI
import LightningDevKit


struct NoteZaps: View {
    
    @Environment(\.managedObjectContext) var viewContext
    
//    // Event that received zaps
//    var event:Event
//
//    var zaps:[Event] {
//        get {
//            Event.zapsForEvent(event.id, context: viewContext)
//        }
//    }
    
    @EnvironmentObject var sp:SocketPool
    
    let id:String
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)], predicate: NSPredicate(value: false))
    var zaps:FetchedResults<Event>
    var zapsSorted:[Event] { zaps.sorted(by: { $0.naiveSats > $1.naiveSats }) }
    
    init(id:String) {
        self.id = id
        _zaps = FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)], predicate: NSPredicate(format: "kind == 9735 AND zappedEventId == %@", id))
    }
    
    var body: some View {
        ScrollView {
            ForEach(zapsSorted) { zap in
                NoteZapRow(event: zap)
            }
            Spacer()
        }
    }
}

struct NoteZapRow: View {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var er:ExchangeRateModel
    @EnvironmentObject var nav:NavigationModel
    @AppStorage("devToggle") var devToggle:Bool = false
    
    // THE ZAP EVENT (FROM CUSTODIAL ZAP PROVIDER)
    var event:Event
    
    // THE INVOICE
    var bolt11:Invoice? {
        get {
            guard let bolt11 = event.bolt11() else { return nil }
            if let pInvoice = Invoice.fromStr(s: bolt11).getValue() {
                return pInvoice
            }
            return nil
        }
    }
    
    // THE AMOUNT PAID
    var sats:Double {
        get {
            if (bolt11?.amountMilliSatoshis() != nil) {
                return Double(bolt11!.amountMilliSatoshis()!)/1000
            }
            return 0
        }
    }
    
    var fiatPrice:String {
        get {
            String(format: "($%.02f)",(Double(sats / 100000000 * er.bitcoinPrice)))
        }
    }
    
    var body: some View {
        
        HStack(alignment: .top) {
            PFP(pubkey: event.zapFromRequest?.pubkey ?? "WTF", pictureUrl: event.zapFromRequest?.contact?.picture)
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {
                        HStack(spacing:3) {
                            Text(event.zapFromRequest?.contact?.authorName ?? "").font(.headline).foregroundColor(.primary)
                                .lineLimit(1)

                            if (event.zapFromRequest?.contact?.nip05veried ?? false) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.blue)
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
                Text("Zapped \(sats.clean) sats \(fiatPrice)")
                Text(event.zapFromRequest?.content ?? "")
            }
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture {
            if (event.zapFromRequest != nil) {
                nav.navigateTo(ContactPath(key: event.zapFromRequest!.pubkey))
            }
        }
        Divider()
    }
}

struct NoteZaps_Previews: PreviewProvider {
    static var previews: some View {
        // Some fake and real Zaps
        
        let odell = PreviewFetcher.fetchEvent("81b2dba2a3d2c92eedab1f966119bda65555d926b97bb41a14c07187472f6159")
        
        VStack {
            NoteZaps(id: "7682031bb0b06d7b9c417dae30141357a74b4f089ebd46226990d418e2def565")
            
            if (odell != nil) {
                NoteZaps(id:"81b2dba2a3d2c92eedab1f966119bda65555d926b97bb41a14c07187472f6159")
            }
        }
        .withPreviewEnvironment()
        
    
    }
}
