//
//  ZapsList.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/02/2023.
//

import SwiftUI
import LightningDevKit

struct ZapsList: View {
    
    @Environment(\.managedObjectContext) var viewContext
    
    // Event that received zaps
    var event:Event
    
    var zaps:[Event] {
        get {
            Event.zapsForEvent(event.id, context: viewContext)
        }
    }
    
    var body: some View {
        ScrollView {
            ForEach(zaps, id:\.self) { zap in
                ZapRow(event: zap)
            }
            Spacer()
        }
    }
}

struct ZapRow: View {
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
    
    // THE PERSON WHO SENT THE SATS
    var contact:Contact? {
        get {
            guard event.zapFromRequest != nil else { return nil }
            return Contact.fetchByPubkey(event.zapFromRequest!.pubkey, context: viewContext)
        }
    }
    
    var body: some View {
        
        HStack {
            Image(systemName: "bolt")
            if (event.zappedEventId == nil) {
                Text("\(sats.clean) sats \(fiatPrice) from")
            }
            
            if (event.zapFromRequest?.name != nil ) {
                Text(event.zapFromRequest!.name)
            }
            else if (event.zapFromRequest?.username != nil) { // Just to add @ to username
                Text("@\(event.zapFromRequest!.username)")
            }
            else if (event.zapFromRequest != nil) {
                Text("@\(event.zapFromRequest!.npub.prefix(11).description)")
            }
            if (event.zappedEventId != nil) {
                Text("zapped \(sats.clean) sats \(fiatPrice) on:")
            }
            if (devToggle) {
                Text("id: \(String(event.id.prefix(5)))")
                    .onTapGesture {
                        UIPasteboard.general.string = event.id
                    }
            }
            Spacer()
        }
        .foregroundColor(.gray)
        .onTapGesture {
            if (event.zapFromRequest != nil) {
                nav.navigateTo(ContactPath(key: event.zapFromRequest!.pubkey))
            }
        }
//        .padding(.leading, 45)
        
        // TODO: What is zap is only to Pubkey, not event???
        if (event.zappedEvent != nil) {
            NoteRowView(event: event.zappedEvent!)
        }
        Divider()
        
//        HStack(alignment: .top) {
//            ProfilePicView(pubkey: zapFromRequest?.pubkey ?? "WTF", contact: zapFromRequest?.contact)
//            VStack(alignment: .leading) {
//                HStack {
//                    VStack(alignment: .leading) {
//                        HStack(spacing:3) {
//                            Text(zapFromRequest?.contact?.authorName ?? "").font(.headline).foregroundColor(.primary)
//                                .lineLimit(1)
//
//                            if (zapFromRequest?.contact?.nip05veried ?? false) {
//                                Image(systemName: "checkmark.seal.fill")
//                                    .font(.system(size: 14))
//                                    .foregroundColor(.blue)
//                            }
//
//                            Group {
//                                Text("@\(zapFromRequest?.contact?.username ?? zapFromRequest?.authorKey ?? "?")").layoutPriority(1)
//                                Text(" · ") //
//                                Text(event.ago).layoutPriority(1) //
//                            }
//                            .foregroundColor(.secondary)
//                            .lineLimit(1)
//                        }
//                    }.multilineTextAlignment(.leading)
//                    Spacer()
//
//                }
//                Text("Zapped \(sats.clean) sats \(fiatPrice)")
//            }
//        }
//        .padding()
//        .contentShape(Rectangle())
//        .onTapGesture {
//            if (zapFromRequest != nil) {
//                nav.navigateTo(ContactPath(key: zapFromRequest!.pubkey))
//            }
//        }
//        Divider()
    }
}

struct ZapsList_Previews: PreviewProvider {
    static var previews: some View {
        
        let event = PreviewFetcher.fetchEvent("7682031bb0b06d7b9c417dae30141357a74b4f089ebd46226990d418e2def565")
        
        VStack {
            if (event != nil) {
                ZapsList(event: event!)
            }
        }
        .withPreviewEnvironment()
        
        // Some fake and real Zaps
        
        let odell = PreviewFetcher.fetchEvent("81b2dba2a3d2c92eedab1f966119bda65555d926b97bb41a14c07187472f6159")
        
        VStack {
            if (odell != nil) {
                ZapsList(event: odell!)
            }
        }
        .withPreviewEnvironment()
        
    
    }
}
