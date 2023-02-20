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
            Event.zapsForEvent(event.id!, context: viewContext)
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
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var nav:NavigationModel
    
    var event:Event
    
    var zapReq:Event? {
        get {
            event.tags_.first(where: { $0.type == "description" })?.event
        }
    }
    
//    var zapFrom:NEvent? {
//        get {
//            let description:Tag? = event.tags_.first(where: { $0.type == "description" })
//            guard description?.index1 != nil else { return nil }
//
//            let decoder = JSONDecoder()
//            if let event = try? decoder.decode(NEvent.self, from: description!.index1!.data(using: .utf8, allowLossyConversion: false)!) {
//                if (try! event.verified()) {
//                    return event
//                }
//            }
//            return nil
//        }
//    }
    
    var bolt11:Invoice? {
        get {
            let bolt11:Tag? = event.tags_.first(where: { $0.type == "bolt11" })
            guard bolt11?.index1 != nil else { return nil }
            if let pInvoice = Invoice.fromStr(s: bolt11!.index1!).getValue() {
                return pInvoice
            }
            return nil
        }
    }
    
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
            String(format: "($%.02f)",(Double(sats / 100000000 * ns.bitcoinPrice)))
        }
    }
    
    var contact:Contact? {
        get {
            guard zapReq != nil else { return nil }
            return Contact.fetchByPubkey(zapReq!.pubkey!, context: viewContext)
        }
    }
    
    var body: some View {
        HStack(alignment: .top) {
            ProfilePicView(pubkey: zapReq?.pubkey ?? "WTF", contact: zapReq?.contact)
//            ProfilePicView(pubkey: zapFrom?.publicKey ?? "WTF", contact: contact)
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {
                        HStack(spacing:3) {
                            Text(zapReq?.contact?.authorName ?? "").font(.headline).foregroundColor(.primary)
                                .lineLimit(1)
                            
                            if (zapReq?.contact?.nip05veried ?? false) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.blue)
                            }
                        
                            Group {
                                Text("@\(zapReq?.contact?.username ?? zapReq?.authorKey ?? "?")").layoutPriority(1)
                                Text(" · ") //
                                Text(event.ago).layoutPriority(1) //
                            }
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        }
                    }.multilineTextAlignment(.leading)
                    Spacer()
                    
                }
                Text("Zapped \(sats.clean) sats \(fiatPrice)")
            }
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture {
            if (zapReq != nil) {
                nav.navigateTo(ContactPath(key: zapReq!.pubkey!))
            }
        }
        Divider()
    }
}

struct ZapsList_Previews: PreviewProvider {
    static var previews: some View {
        
        let event = PreviewFetcher.fetchEvent("7682031bb0b06d7b9c417dae30141357a74b4f089ebd46226990d418e2def565")
        
        VStack {
            ZapsList(event: event!)
        }
        .withPreviewEnvironment()
        
        // Some fake and real Zaps
        
        let odell = PreviewFetcher.fetchEvent("81b2dba2a3d2c92eedab1f966119bda65555d926b97bb41a14c07187472f6159")
        
        VStack {
            ZapsList(event: odell!)
        }
        .withPreviewEnvironment()
        
    
    }
}
